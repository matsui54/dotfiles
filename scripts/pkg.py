#!/usr/bin/env python3
"""
Lightweight, zero-dependency user-space package manager.
Installs prebuilt binaries from GitHub Releases (preferring static/musl builds)
into ~/.local/opt/<name> and symlinks executables into ~/.local/bin.
"""

import argparse
import fnmatch
import gzip
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
from typing import Any, Callable, Dict, List, Optional, Tuple
import urllib.request
import zipfile

LOCAL_DIR = Path.home() / ".local"
OPT_DIR = LOCAL_DIR / "opt"
BIN_DIR = LOCAL_DIR / "bin"
STATE_FILE = OPT_DIR / ".pkg_state.json"


def get_glibc_version() -> Tuple[int, int]:
    try:
        ver_str = os.confstr("CS_GNU_LIBC_VERSION")
        if ver_str:
            parts = ver_str.split()[-1].split(".")
            return (int(parts[0]), int(parts[1]))
    except Exception:
        pass
    return (2, 35)


def nvim_repo() -> str:
    # Fallback to neovim-releases on older Linux distros (glibc < 2.32, e.g. RHEL7/8, Ubuntu 18.04)
    if get_glibc_version() < (2, 32):
        return "neovim/neovim-releases"
    return "neovim/neovim"


def slang_server_asset() -> str:
    if get_glibc_version() < (2, 32):
        return "slang-server-old-linux-x64-gcc.tar.gz"
    return "slang-server-linux-x64.tar.gz"


# Package definitions:
# - repo: GitHub "owner/repo" (or callable returning "owner/repo")
# - asset: glob pattern matching release asset filename
# - bins: list of relative paths inside extracted directory (or binary name for .gz/single file)
# - strip: whether to strip top-level directory when extracting archives (default: True)
# - default: whether installed by default on `pkg install` with no args
PACKAGES: Dict[str, Dict[str, Any]] = {
    "nvim": {
        "custom_installer": "neovim_source",
        "bins": ["nvim"],
        "default": True,
        "desc": "Neovim editor (built from source into ~/.local/nvim)",
    },
    "nvim-bin": {
        "repo": nvim_repo,
        "asset": "nvim-linux-x86_64.tar.gz",
        "bins": ["bin/nvim"],
        "strip": True,
        "default": False,
        "desc": "Neovim editor (prebuilt binary)",
    },
    "rg": {
        "repo": "BurntSushi/ripgrep",
        "asset": "ripgrep-*-x86_64-unknown-linux-musl.tar.gz",
        "bins": ["rg"],
        "strip": True,
        "default": True,
        "desc": "ripgrep fast search tool (static musl)",
    },
    "fd": {
        "repo": "sharkdp/fd",
        "asset": "fd-*-x86_64-unknown-linux-musl.tar.gz",
        "bins": ["fd"],
        "strip": True,
        "default": True,
        "desc": "fd fast file finder (static musl)",
    },
    "bat": {
        "repo": "sharkdp/bat",
        "asset": "bat-*-x86_64-unknown-linux-musl.tar.gz",
        "bins": ["bat"],
        "strip": True,
        "default": True,
        "desc": "bat cat clone with syntax highlighting (static musl)",
    },
    "fzf": {
        "repo": "junegunn/fzf",
        "asset": "fzf-*-linux_amd64.tar.gz",
        "bins": ["fzf"],
        "strip": False,
        "default": True,
        "desc": "fzf command-line fuzzy finder",
    },
    "gh": {
        "repo": "cli/cli",
        "asset": "gh_*_linux_amd64.tar.gz",
        "bins": ["bin/gh"],
        "strip": True,
        "default": True,
        "desc": "GitHub CLI",
    },
    "ghq": {
        "repo": "x-motemen/ghq",
        "asset": "ghq_linux_amd64.zip",
        "bins": ["ghq"],
        "strip": True,
        "default": True,
        "desc": "ghq remote repository manager",
    },
    "tree-sitter": {
        "repo": "tree-sitter/tree-sitter",
        "asset": "tree-sitter-linux-x64.gz",
        "bins": ["tree-sitter"],
        "strip": False,
        "default": True,
        "desc": "tree-sitter CLI (for nvim-treesitter parser compilation)",
    },
    "rust": {
        "custom_installer": "rustup",
        "bins": [],
        "default": True,
        "desc": "Rust toolchain & cargo via rustup (~/.cargo)",
    },
    # Optional packages (install via `pkg install <name>` or `pkg install --all`)
    "lua-language-server": {
        "repo": "LuaLS/lua-language-server",
        "asset": "lua-language-server-*-linux-x64.tar.gz",
        "bins": ["bin/lua-language-server"],
        "strip": False,
        "default": False,
        "desc": "Lua Language Server",
    },
    "clangd": {
        "repo": "clangd/clangd",
        "asset": "clangd-linux-*.zip",
        "bins": ["bin/clangd"],
        "strip": True,
        "default": False,
        "desc": "clangd C/C++ LSP server",
    },
    "slang-server": {
        "repo": "hudson-trading/slang-server",
        "asset": slang_server_asset,
        "bins": ["slang-server"],
        "strip": False,
        "default": False,
        "desc": "SystemVerilog LSP server",
    },
    "pyright": {
        "npm": "pyright",
        "depends": ["node"],
        "bins": [
            "pyright:index.js",
            "pyright-langserver:langserver.index.js",
        ],
        "strip": True,
        "default": False,
        "desc": "pyright Python static type checker and LSP server",
    },
    "node": {
        "custom_resolver": "node",
        "bins": ["bin/node", "bin/npm", "bin/npx"],
        "strip": True,
        "default": False,
        "desc": "Node.js LTS runtime (also used by copilot.vim & pyright)",
    },
    "uv": {
        "repo": "astral-sh/uv",
        "asset": "uv-x86_64-unknown-linux-musl.tar.gz",
        "bins": ["uv", "uvx"],
        "strip": True,
        "default": False,
        "desc": "uv Python package and runtime manager (static musl)",
    },
    "zig": {
        "custom_resolver": "zig",
        "bins": ["zig"],
        "strip": True,
        "default": False,
        "desc": "Zig compiler (master branch)",
    },
    "go": {
        "custom_resolver": "go",
        "bins": ["bin/go", "bin/gofmt"],
        "strip": True,
        "default": False,
        "desc": "Go programming language toolchain",
    },
}


def load_state() -> Dict[str, str]:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_state(state: Dict[str, str]) -> None:
    OPT_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def http_get(url: str, is_api: bool = False) -> urllib.request. addinfourl:
    headers = {"User-Agent": "dotfiles-pkg-manager/1.0"}
    if is_api:
        headers["Accept"] = "application/vnd.github+json"
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req)


def resolve_github_release(repo: str, asset_pattern: str) -> Tuple[str, str, int]:
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    with http_get(url, is_api=True) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    tag = data["tag_name"]
    for asset in data.get("assets", []):
        name = asset["name"]
        if fnmatch.fnmatch(name, asset_pattern):
            return tag, asset["browser_download_url"], int(asset.get("size", 0))

    available = [a["name"] for a in data.get("assets", [])]
    raise RuntimeError(
        f"No asset matching '{asset_pattern}' found in {repo}@{tag}. Available: {available}"
    )


def resolve_zig() -> Tuple[str, str, int]:
    with http_get("https://ziglang.org/download/index.json") as resp:
        info = json.loads(resp.read().decode("utf-8"))
    master = info["master"]
    version = master["version"]
    pack = master["x86_64-linux"]
    return version, pack["tarball"], int(pack.get("size", 0))


def resolve_go() -> Tuple[str, str, int]:
    with http_get("https://go.dev/dl/?mode=json") as resp:
        releases = json.loads(resp.read().decode("utf-8"))
    latest = releases[0]
    version = latest["version"]
    for f in latest.get("files", []):
        if f.get("os") == "linux" and f.get("arch") == "amd64" and f.get("kind") == "archive":
            url = f"https://go.dev/dl/{f['filename']}"
            return version, url, int(f.get("size", 0))
    raise RuntimeError(f"No linux-amd64 archive found in Go release {version}")


def resolve_node() -> Tuple[str, str, int]:
    with http_get("https://nodejs.org/dist/index.json") as resp:
        releases = json.loads(resp.read().decode("utf-8"))
    latest_lts = next((r for r in releases if r.get("lts")), releases[0])
    version = latest_lts["version"]
    url = f"https://nodejs.org/dist/{version}/node-{version}-linux-x64.tar.xz"
    return version, url, 0


def resolve_npm(pkg_name: str) -> Tuple[str, str, int]:
    with http_get(f"https://registry.npmjs.org/{pkg_name}/latest") as resp:
        data = json.loads(resp.read().decode("utf-8"))
    version = data["version"]
    url = data["dist"]["tarball"]
    return version, url, 0


def resolve_package(name: str, spec: Dict[str, Any]) -> Tuple[str, str, int]:
    if spec.get("custom_resolver") == "zig":
        return resolve_zig()
    if spec.get("custom_resolver") == "go":
        return resolve_go()
    if spec.get("custom_resolver") == "node":
        return resolve_node()
    if "npm" in spec:
        return resolve_npm(spec["npm"])
    repo = spec["repo"]() if callable(spec["repo"]) else spec["repo"]
    asset = spec["asset"]() if callable(spec["asset"]) else spec["asset"]
    return resolve_github_release(repo, asset)


def download_bytes(url: str, expected_size: int = 0) -> bytes:
    buf = io.BytesIO()
    with http_get(url) as resp:
        total_size = expected_size or int(resp.headers.get("Content-Length", 0))
        downloaded = 0
        block_size = 65536
        while True:
            chunk = resp.read(block_size)
            if not chunk:
                break
            buf.write(chunk)
            downloaded += len(chunk)
            if total_size > 0:
                pct = (downloaded / total_size) * 100
                print(f"\r  Downloading... {pct:5.1f}% ({downloaded // 1024} KB)", end="", flush=True)
            else:
                print(f"\r  Downloading... {downloaded // 1024} KB", end="", flush=True)
    print()
    return buf.getvalue()


def extract_archive(data: bytes, url: str, dest_dir: Path, strip: bool, bins: List[str]) -> None:
    if dest_dir.exists():
        shutil.rmtree(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)

    lower_url = url.lower()
    if lower_url.endswith((".tar.gz", ".tgz", ".tar.xz", ".txz")):
        mode = "r:xz" if lower_url.endswith((".tar.xz", ".txz")) else "r:gz"
        with tarfile.open(fileobj=io.BytesIO(data), mode=mode) as tar:
            for member in tar.getmembers():
                parts = Path(member.name).parts
                if strip:
                    if len(parts) <= 1:
                        continue
                    rel_path = Path(*parts[1:])
                else:
                    rel_path = Path(*parts)

                if ".." in rel_path.parts:
                    continue
                target = dest_dir / rel_path

                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.issym():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    target.symlink_to(member.linkname)
                elif member.isfile():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    f = tar.extractfile(member)
                    if f is not None:
                        target.write_bytes(f.read())
                        target.chmod(member.mode)

    elif lower_url.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            for info in zf.infolist():
                parts = Path(info.filename).parts
                if strip:
                    if len(parts) <= 1:
                        continue
                    rel_path = Path(*parts[1:])
                else:
                    rel_path = Path(*parts)

                if ".." in rel_path.parts:
                    continue
                target = dest_dir / rel_path

                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(zf.read(info.filename))
                    perm = (info.external_attr >> 16) & 0o777
                    if perm:
                        target.chmod(perm)

    elif lower_url.endswith(".gz"):
        # Single gzipped binary (e.g. tree-sitter-linux-x64.gz)
        raw = gzip.decompress(data)
        bin_rel = Path(bins[0])
        target = dest_dir / bin_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        target.chmod(0o755)

    else:
        raise RuntimeError(f"Unsupported archive format: {url}")


def install_rustup(force: bool = False) -> None:
    cargo_bin = Path.home() / ".cargo" / "bin" / "cargo"
    rustup_bin = Path.home() / ".cargo" / "bin" / "rustup"
    rustc_bin = Path.home() / ".cargo" / "bin" / "rustc"
    state = load_state()

    if cargo_bin.exists() and rustup_bin.exists():
        if force:
            print("[rust] Updating toolchain via rustup...")
            subprocess.run([str(rustup_bin), "update"], check=True)
        else:
            ver = state.get("rust", "installed")
            print(f"[rust] Already installed ({ver})")
            return
    else:
        print("[rust] Installing rustup and cargo to ~/.cargo...")
        with http_get("https://sh.rustup.rs") as resp:
            installer = resp.read()
        subprocess.run(
            ["sh", "-s", "--", "-y", "--no-modify-path"],
            input=installer,
            check=True,
        )

    if rustc_bin.exists():
        out = subprocess.check_output([str(rustc_bin), "--version"], text=True).strip()
        # e.g. "rustc 1.85.0 (4d91de4e4 2025-02-17)" -> "1.85.0"
        parts = out.split()
        ver = parts[1] if len(parts) > 1 else "installed"
        state["rust"] = ver
        save_state(state)
        print(f"[rust] Done ({ver})")


def parse_bin_spec(b: str) -> Tuple[str, str]:
    if ":" in b:
        link_name, rel_target = b.split(":", 1)
        return link_name, rel_target
    return Path(b).name, b


def install_neovim_from_source(force: bool = False) -> None:
    # 1. Determine ghq root or fallback
    ghq_root = Path.home() / "ghq"
    if shutil.which("ghq"):
        try:
            out = subprocess.check_output(["ghq", "root"], text=True).strip()
            if out:
                ghq_root = Path(out)
        except Exception:
            pass
    src_dir = ghq_root / "github.com" / "neovim" / "neovim"
    dest_prefix = Path.home() / ".local" / "nvim"
    nvim_bin = dest_prefix / "bin" / "nvim"
    state = load_state()

    # 2. Check build prerequisites
    missing = [
        t for t in ["make", "gcc", "cmake", "gettext"]
        if not shutil.which(t) and not (BIN_DIR / t).exists()
    ]
    if missing:
        raise RuntimeError(
            f"Missing required build tools for Neovim: {', '.join(missing)}.\n"
            f"Please install them via system package manager (e.g. sudo apt install -y build-essential cmake gettext ninja-build)"
        )

    # 3. Clone or update repository
    need_build = force or not nvim_bin.exists() or not (BIN_DIR / "nvim").exists()

    if not src_dir.exists():
        print(f"[nvim] Cloning neovim/neovim to {src_dir}...")
        src_dir.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "https://github.com/neovim/neovim.git", str(src_dir)], check=True)
        need_build = True
    else:
        print(f"[nvim] Updating repository in {src_dir}...")
        subprocess.run(["git", "checkout", "master"], cwd=src_dir, check=True)
        old_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=src_dir, text=True).strip()
        subprocess.run(["git", "pull", "--rebase"], cwd=src_dir, check=True)
        new_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=src_dir, text=True).strip()
        if old_head != new_head:
            need_build = True

    if not need_build and (BIN_DIR / "nvim").exists():
        ver = state.get("nvim", "installed (source)")
        print(f"[nvim] Already up to date ({ver})")
        return

    # 4. Build and install
    print(f"[nvim] Building Neovim with 'make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX={dest_prefix} install'...")
    env = os.environ.copy()
    env["PATH"] = f"{BIN_DIR}:{env.get('PATH', '')}"
    subprocess.run(
        [
            "make",
            "CMAKE_BUILD_TYPE=Release",
            f"CMAKE_INSTALL_PREFIX={dest_prefix}",
            "install",
        ],
        cwd=src_dir,
        env=env,
        check=True,
    )

    # 5. Link binary
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    link_path = BIN_DIR / "nvim"
    if link_path.exists() or link_path.is_symlink():
        link_path.unlink()
    link_path.symlink_to(nvim_bin)
    print(f"  Linked {link_path} -> {nvim_bin}")

    # 6. Record state
    try:
        ver_line = subprocess.check_output([str(nvim_bin), "--version"], text=True).splitlines()[0]
        ver = ver_line.split()[1]
    except Exception:
        ver = "source"
    state["nvim"] = ver
    save_state(state)
    print(f"[nvim] Done ({ver})")


def install_package(name: str, force: bool = False) -> None:
    if name not in PACKAGES:
        raise ValueError(f"Unknown package: {name}")

    spec = PACKAGES[name]
    for dep in spec.get("depends", []):
        install_package(dep, force=False)

    if spec.get("custom_installer") == "rustup":
        install_rustup(force=force)
        return
    if spec.get("custom_installer") == "neovim_source":
        install_neovim_from_source(force=force)
        return

    state = load_state()
    dest_dir = OPT_DIR / name

    print(f"[{name}] Checking latest version...")
    version, url, size = resolve_package(name, spec)
    installed_ver = state.get(name)

    bins_exist = all((BIN_DIR / parse_bin_spec(b)[0]).exists() for b in spec["bins"])
    if not force and installed_ver == version and dest_dir.exists() and bins_exist:
        print(f"[{name}] Already up to date ({version})")
        return

    print(f"[{name}] Installing {version} from {url}")
    data = download_bytes(url, size)
    print(f"  Extracting to {dest_dir}...")
    extract_archive(data, url, dest_dir, spec.get("strip", True), spec["bins"])

    BIN_DIR.mkdir(parents=True, exist_ok=True)
    for b in spec["bins"]:
        link_name, rel_target = parse_bin_spec(b)
        src_bin = dest_dir / rel_target
        if not src_bin.exists():
            matches = [
                p for p in dest_dir.rglob(Path(rel_target).name)
                if p.is_file() and not p.is_symlink()
            ]
            if matches:
                src_bin = matches[0]
            else:
                raise RuntimeError(f"Expected binary not found after extraction: {src_bin}")
        src_bin.chmod(src_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        link_path = BIN_DIR / link_name
        if link_path.exists() or link_path.is_symlink():
            link_path.unlink()
        link_path.symlink_to(src_bin)
        print(f"  Linked {link_path} -> {src_bin}")

    state[name] = version
    save_state(state)
    print(f"[{name}] Done ({version})")


def remove_package(name: str) -> None:
    if name not in PACKAGES:
        raise ValueError(f"Unknown package: {name}")
    spec = PACKAGES[name]
    if spec.get("custom_installer") == "neovim_source":
        link_path = BIN_DIR / "nvim"
        if link_path.is_symlink() or link_path.exists():
            link_path.unlink()
            print(f"[nvim] Removed link {link_path}")
        dest_prefix = Path.home() / ".local" / "nvim"
        if dest_prefix.exists():
            shutil.rmtree(dest_prefix)
            print(f"[nvim] Removed directory {dest_prefix}")
        state = load_state()
        if name in state:
            del state[name]
            save_state(state)
        return

    dest_dir = OPT_DIR / name
    for b in spec["bins"]:
        link_name, _ = parse_bin_spec(b)
        link_path = BIN_DIR / link_name
        if link_path.is_symlink() or link_path.exists():
            link_path.unlink()
            print(f"[{name}] Removed link {link_path}")
    if dest_dir.exists():
        shutil.rmtree(dest_dir)
        print(f"[{name}] Removed directory {dest_dir}")
    state = load_state()
    if name in state:
        del state[name]
        save_state(state)


def list_packages() -> None:
    state = load_state()
    print(f"{'PACKAGE':<22} {'DEFAULT':<9} {'INSTALLED':<16} {'DESCRIPTION'}")
    print("-" * 78)
    for name, spec in PACKAGES.items():
        is_def = "yes" if spec.get("default") else "no"
        ver = state.get(name, "-")
        if spec.get("custom_installer") == "rustup":
            bins_ok = (Path.home() / ".cargo" / "bin" / "cargo").exists()
        elif spec.get("custom_installer") == "neovim_source":
            bins_ok = (Path.home() / ".local" / "nvim" / "bin" / "nvim").exists() and (BIN_DIR / "nvim").exists()
        else:
            bins_ok = all((BIN_DIR / parse_bin_spec(b)[0]).exists() for b in spec["bins"])
        if ver != "-" and not bins_ok:
            ver = f"{ver} (broken)"
        elif ver == "-" and bins_ok:
            ver = "installed"
        print(f"{name:<22} {is_def:<9} {ver:<16} {spec.get('desc', '')}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Lightweight user-space binary package manager (~/.local)"
    )
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("list", aliases=["status", "ls"], help="List packages and installation status")

    p_install = sub.add_parser("install", aliases=["update", "up", "i"], help="Install or update packages")
    p_install.add_argument("packages", nargs="*", help="Package names (default: all default packages)")
    p_install.add_argument("-a", "--all", action="store_true", help="Install all packages including optional ones")
    p_install.add_argument("-f", "--force", action="store_true", help="Force reinstall even if up to date")

    p_remove = sub.add_parser("remove", aliases=["rm", "uninstall"], help="Remove packages")
    p_remove.add_argument("packages", nargs="+", help="Package names to remove")

    args = parser.parse_args()

    if not args.cmd or args.cmd in ("list", "status", "ls"):
        list_packages()
        return

    if args.cmd in ("install", "update", "up", "i"):
        if args.all:
            targets = list(PACKAGES.keys())
        elif args.packages:
            targets = args.packages
        else:
            targets = [k for k, v in PACKAGES.items() if v.get("default")]

        failed = []
        for pkg in targets:
            try:
                install_package(pkg, force=args.force)
            except Exception as e:
                print(f"[{pkg}] ERROR: {e}", file=sys.stderr)
                failed.append(pkg)
        if failed:
            sys.exit(1)

    elif args.cmd in ("remove", "rm", "uninstall"):
        for pkg in args.packages:
            remove_package(pkg)


if __name__ == "__main__":
    main()

