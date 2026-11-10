#!/usr/bin/env python3
"""
Package definitions and custom recipes for user-space package manager.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any, Dict, Optional

from pkglib import (
    BIN_DIR,
    LOCAL_DIR,
    SRC_DIR,
    ArchiveSpec,
    CargoInstall,
    Custom,
    GitHubRelease,
    GoInstall,
    NpmPackage,
    Pkg,
    UrlArchive,
    UvTool,
    download_bytes,
    fetch_json,
    http_get,
    link_executable,
    run_cli,
    unlink_bins,
    verify_sha256,
)


# ============================================================================
# Custom Resolvers & Recipes
# ============================================================================


def resolve_zig() -> ArchiveSpec:
    info = fetch_json("https://ziglang.org/download/index.json")
    master = info["master"]
    pack = master["x86_64-linux"]
    return ArchiveSpec(
        version=master["version"],
        url=pack["tarball"],
        size=int(pack.get("size", 0)),
        sha256=pack.get("shasum"),
    )


def resolve_go() -> ArchiveSpec:
    releases = fetch_json("https://go.dev/dl/?mode=json")
    latest = releases[0]
    version = latest["version"]
    for f in latest.get("files", []):
        if f.get("os") == "linux" and f.get("arch") == "amd64" and f.get("kind") == "archive":
            return ArchiveSpec(
                version=version,
                url=f"https://go.dev/dl/{f['filename']}",
                size=int(f.get("size", 0)),
                sha256=f.get("sha256"),
            )
    raise RuntimeError(f"No linux-amd64 archive found in Go release {version}")


def resolve_node() -> ArchiveSpec:
    releases = fetch_json("https://nodejs.org/dist/index.json")
    latest_lts = next((r for r in releases if r.get("lts")), releases[0])
    version = latest_lts["version"]
    filename = f"node-{version}-linux-x64.tar.xz"
    url = f"https://nodejs.org/dist/{version}/{filename}"
    sha256 = None
    with http_get(f"https://nodejs.org/dist/{version}/SHASUMS256.txt") as resp:
        for line in resp.read().decode("utf-8").splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1] == filename:
                sha256 = parts[0]
                break
    return ArchiveSpec(version=version, url=url, size=0, sha256=sha256)


def lock_neovim_source(_pkg: Pkg) -> Dict[str, Any]:
    """Resolve Neovim 'stable' release version and exact commit SHA."""
    rel = fetch_json("https://api.github.com/repos/neovim/neovim/releases/latest", is_api=True)
    tag_name = rel["tag_name"]
    out = subprocess.check_output(
        [
            "git",
            "ls-remote",
            "https://github.com/neovim/neovim.git",
            f"refs/tags/{tag_name}",
            f"refs/tags/{tag_name}^{{}}",
            "refs/tags/stable",
            "refs/tags/stable^{}",
        ],
        text=True,
    )
    ref_map: Dict[str, str] = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2:
            ref_map[parts[1]] = parts[0]

    commit = (
        ref_map.get(f"refs/tags/{tag_name}^{{}}")
        or ref_map.get(f"refs/tags/{tag_name}")
        or ref_map.get("refs/tags/stable^{}")
        or ref_map.get("refs/tags/stable")
    )
    if not commit:
        raise RuntimeError("Failed to resolve commit SHA for Neovim stable release")
    return {"version": tag_name, "commit": commit}


def install_neovim_source(
    pkg: Pkg,
    force: bool,
    state: Dict[str, str],
    lock_entry: Optional[Dict[str, Any]] = None,
) -> Optional[str]:
    src_dir = SRC_DIR / "neovim"
    dest_prefix = LOCAL_DIR / "nvim"
    nvim_bin = dest_prefix / "bin" / "nvim"

    missing = [
        t
        for t in ["make", "gcc", "cmake", "gettext"]
        if not shutil.which(t) and not (BIN_DIR / t).exists()
    ]
    if missing:
        raise RuntimeError(
            f"Missing required build tools for Neovim: {', '.join(missing)}.\n"
            f"Please install them via system package manager "
            f"(e.g. sudo apt install -y build-essential cmake gettext ninja-build)"
        )

    if lock_entry is None:
        lock_entry = lock_neovim_source(pkg)
    target_version = lock_entry["version"]
    target_commit = lock_entry["commit"]

    if not force and state.get(pkg.name) == target_version and is_neovim_installed(pkg):
        if src_dir.exists():
            try:
                cur_head = subprocess.check_output(
                    ["git", "rev-parse", "HEAD"], cwd=src_dir, text=True
                ).strip()
                if cur_head == target_commit:
                    print(f"[{pkg.name}] Already up to date ({target_version})")
                    return None
            except Exception:
                pass
        else:
            print(f"[{pkg.name}] Already up to date ({target_version})")
            return None

    if not src_dir.exists():
        print(f"[{pkg.name}] Cloning neovim/neovim to {src_dir}...")
        src_dir.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "clone", "https://github.com/neovim/neovim.git", str(src_dir)], check=True
        )
    else:
        print(f"[{pkg.name}] Fetching latest commits/tags in {src_dir}...")
        subprocess.run(
            ["git", "fetch", "--tags", "--force", "origin"], cwd=src_dir, check=True
        )

    print(f"[{pkg.name}] Checking out locked stable commit {target_commit[:12]} ({target_version})...")
    subprocess.run(["git", "checkout", "--detach", target_commit], cwd=src_dir, check=True)
    actual_head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=src_dir, text=True
    ).strip()
    if actual_head.lower() != target_commit.lower():
        raise RuntimeError(
            f"[{pkg.name}] Commit verification failed! Expected {target_commit}, got {actual_head}"
        )

    print(
        f"[{pkg.name}] Building Neovim ({target_version}) with "
        f"'make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX={dest_prefix} install'..."
    )
    env = os.environ.copy()
    env["PATH"] = f"{BIN_DIR}:{env.get('PATH', '')}"
    subprocess.run(
        ["make", "CMAKE_BUILD_TYPE=Release", f"CMAKE_INSTALL_PREFIX={dest_prefix}", "install"],
        cwd=src_dir,
        env=env,
        check=True,
    )

    link_executable(nvim_bin, "nvim")
    return target_version


def remove_neovim_source(pkg: Pkg) -> None:
    unlink_bins(pkg.name, ["nvim"])
    dest_prefix = LOCAL_DIR / "nvim"
    if dest_prefix.exists():
        shutil.rmtree(dest_prefix)
        print(f"[{pkg.name}] Removed directory {dest_prefix}")


def is_neovim_installed(_pkg: Pkg) -> bool:
    return (LOCAL_DIR / "nvim" / "bin" / "nvim").exists() and (BIN_DIR / "nvim").exists()


RUSTUP_INIT_URL = (
    "https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
)
RUSTUP_INIT_SHA256_URL = f"{RUSTUP_INIT_URL}.sha256"


def lock_rustup(_pkg: Pkg) -> Dict[str, Any]:
    rel = fetch_json("https://api.github.com/repos/rust-lang/rust/releases/latest", is_api=True)
    version = rel["tag_name"]
    with http_get(RUSTUP_INIT_SHA256_URL) as resp:
        sha256_text = resp.read().decode("utf-8").strip()
    sha256 = sha256_text.split()[0].lower()
    if len(sha256) != 64:
        raise RuntimeError(f"Invalid SHA256 from {RUSTUP_INIT_SHA256_URL}: {sha256_text}")
    return {
        "version": version,
        "url": RUSTUP_INIT_URL,
        "sha256": sha256,
    }


def install_rustup(
    pkg: Pkg,
    force: bool,
    state: Dict[str, str],
    lock_entry: Optional[Dict[str, Any]] = None,
) -> Optional[str]:
    cargo_dir = Path.home() / ".cargo" / "bin"
    rustup_bin = cargo_dir / "rustup"

    if lock_entry is None:
        lock_entry = lock_rustup(pkg)
    target_version = lock_entry["version"]
    url = lock_entry["url"]
    expected_sha256 = lock_entry["sha256"]

    installed_ver = state.get(pkg.name)
    if not force and installed_ver == target_version and is_rust_installed(pkg):
        print(f"[{pkg.name}] Already up to date ({target_version})")
        return None

    if is_rust_installed(pkg) and rustup_bin.exists():
        print(f"[{pkg.name}] Installing/setting Rust toolchain {target_version} via rustup...")
        subprocess.run(
            [str(rustup_bin), "toolchain", "install", target_version], check=True
        )
        subprocess.run([str(rustup_bin), "default", target_version], check=True)
    else:
        print(f"[{pkg.name}] Downloading rustup-init from {url}...")
        data = download_bytes(url)
        verify_sha256(data, expected_sha256, pkg.name)
        print(f"  Verified SHA256: {expected_sha256[:16]}...")

        with tempfile.TemporaryDirectory(prefix="rustup_init_") as tmpdir:
            init_bin = Path(tmpdir) / "rustup-init"
            init_bin.write_bytes(data)
            init_bin.chmod(0o755)
            subprocess.run(
                [
                    str(init_bin),
                    "-y",
                    "--no-modify-path",
                    "--default-toolchain",
                    target_version,
                ],
                check=True,
            )

    return target_version


def remove_rustup(pkg: Pkg) -> None:
    rustup_bin = Path.home() / ".cargo" / "bin" / "rustup"
    if rustup_bin.exists():
        subprocess.run([str(rustup_bin), "self", "uninstall", "-y"], check=True)
        print(f"[{pkg.name}] Uninstalled rustup")


def is_rust_installed(_pkg: Pkg) -> bool:
    return (Path.home() / ".cargo" / "bin" / "cargo").exists()


# ============================================================================
# Package Catalog
# ============================================================================

PACKAGES = [
    # --- Default Core Packages ---
    Pkg(
        "nvim",
        default=True,
        desc="Neovim editor (built from locked stable commit into ~/.local/nvim)",
        source=Custom(
            install=install_neovim_source,
            remove=remove_neovim_source,
            is_installed=is_neovim_installed,
            lock=lock_neovim_source,
        ),
    ),
    Pkg(
        "nvim-bin",
        desc="Neovim editor (prebuilt binary)",
        source=GitHubRelease(
            repo="neovim/neovim",
            asset="nvim-linux-x86_64.tar.gz",
            old_glibc_repo="neovim/neovim-releases",
            bins=["bin/nvim"],
        ),
    ),
    Pkg(
        "rg",
        default=True,
        desc="ripgrep fast search tool (static musl)",
        source=GitHubRelease(
            repo="BurntSushi/ripgrep",
            asset="ripgrep-*-x86_64-unknown-linux-musl.tar.gz",
            bins=["rg"],
        ),
    ),
    Pkg(
        "fd",
        default=True,
        desc="fd fast file finder (static musl)",
        source=GitHubRelease(
            repo="sharkdp/fd",
            asset="fd-*-x86_64-unknown-linux-musl.tar.gz",
            bins=["fd"],
        ),
    ),
    Pkg(
        "bat",
        default=True,
        desc="bat cat clone with syntax highlighting (static musl)",
        source=GitHubRelease(
            repo="sharkdp/bat",
            asset="bat-*-x86_64-unknown-linux-musl.tar.gz",
            bins=["bat"],
        ),
    ),
    Pkg(
        "fzf",
        default=True,
        desc="fzf command-line fuzzy finder",
        source=GitHubRelease(
            repo="junegunn/fzf",
            asset="fzf-*-linux_amd64.tar.gz",
            bins=["fzf"],
            strip=False,
        ),
    ),
    Pkg(
        "rust",
        default=True,
        desc="Rust toolchain & cargo via rustup (~/.cargo)",
        source=Custom(
            install=install_rustup,
            remove=remove_rustup,
            is_installed=is_rust_installed,
            lock=lock_rustup,
        ),
    ),
    # --- Optional Packages (LSPs, Runtimes, Tools) ---
    Pkg(
        "tree-sitter",
        desc="tree-sitter CLI (built from source via cargo)",
        source=CargoInstall(crate="tree-sitter-cli", bins=["tree-sitter"]),
    ),
    Pkg(
        "zoxide",
        desc="zoxide",
        source=CargoInstall(crate="zoxide", bins=["zoxide"]),
    ),
    Pkg(
        "lua-language-server",
        desc="Lua Language Server",
        source=GitHubRelease(
            repo="LuaLS/lua-language-server",
            asset="lua-language-server-*-linux-x64.tar.gz",
            bins=["bin/lua-language-server"],
            strip=False,
        ),
    ),
    Pkg(
        "clangd",
        desc="clangd C/C++ LSP server",
        source=GitHubRelease(
            repo="clangd/clangd",
            asset="clangd-linux-*.zip",
            bins=["bin/clangd"],
        ),
    ),
    Pkg(
        "slang-server",
        desc="SystemVerilog LSP server",
        source=GitHubRelease(
            repo="hudson-trading/slang-server",
            asset="slang-server-linux-x64.tar.gz",
            old_glibc_asset="slang-server-old-linux-x64-gcc.tar.gz",
            bins=["slang-server"],
            strip=False,
        ),
    ),
    Pkg(
        "pyright",
        desc="pyright Python static type checker and LSP server",
        source=NpmPackage(
            package="pyright",
            bins=["pyright:index.js", "pyright-langserver:langserver.index.js"],
        ),
    ),
    Pkg(
        "node",
        desc="Node.js LTS runtime (also used by copilot.vim & pyright)",
        source=UrlArchive(resolver=resolve_node, bins=["bin/node", "bin/npm", "bin/npx"]),
    ),
    Pkg(
        "uv",
        desc="uv Python package and runtime manager (static musl)",
        source=GitHubRelease(
            repo="astral-sh/uv",
            asset="uv-x86_64-unknown-linux-musl.tar.gz",
            bins=["uv", "uvx"],
        ),
    ),
    Pkg(
        "zig",
        desc="Zig compiler (master branch)",
        source=UrlArchive(resolver=resolve_zig, bins=["zig"]),
    ),
    Pkg(
        "go",
        desc="Go programming language toolchain",
        source=UrlArchive(resolver=resolve_go, bins=["bin/go", "bin/gofmt"]),
    ),
    Pkg(
        "mcp-language-server",
        desc="Language server for Model Context Protocol (MCP)",
        source=GoInstall(
            package="github.com/isaacphi/mcp-language-server",
            bins=["mcp-language-server"],
        ),
    ),
    Pkg(
        "serena",
        desc="Serena coding agent toolkit (via uv tool)",
        source=UvTool(
            package="serena-agent",
            bins=["serena"],
            python="3.13",
        ),
    ),
    Pkg(
        "verible",
        default=False,
        desc="verible language server",
        source=GitHubRelease(
            repo="chipsalliance/verible",
            asset="verible-*-linux-static-x86_64.tar.gz",
            bins=["verible-verilog-ls"],
        ),
    ),
    Pkg(
        "konata",
        default=False,
        desc="Pipeline visualizer",
        source=GitHubRelease(
            repo="shioyadan/Konata",
            asset="konata-*.zip",
            bins=["konata.sh"],
        ),
    ),
]


if __name__ == "__main__":
    run_cli(PACKAGES)
