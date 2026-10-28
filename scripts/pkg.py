#!/usr/bin/env python3
"""
Package definitions and custom recipes for user-space package manager.
"""

import os
from pathlib import Path
import shutil
import subprocess
from typing import Dict, Optional, Tuple

from pkglib import (
    BIN_DIR,
    LOCAL_DIR,
    SRC_DIR,
    CargoInstall,
    Custom,
    GitHubRelease,
    GoInstall,
    NpmPackage,
    Pkg,
    UrlArchive,
    UvTool,
    fetch_json,
    glibc_version,
    http_get,
    link_executable,
    run_cli,
    unlink_bins,
)


# ============================================================================
# Custom Resolvers & Recipes
# ============================================================================


def resolve_zig() -> Tuple[str, str, int]:
    info = fetch_json("https://ziglang.org/download/index.json")
    master = info["master"]
    pack = master["x86_64-linux"]
    return master["version"], pack["tarball"], int(pack.get("size", 0))


def resolve_go() -> Tuple[str, str, int]:
    releases = fetch_json("https://go.dev/dl/?mode=json")
    latest = releases[0]
    version = latest["version"]
    for f in latest.get("files", []):
        if f.get("os") == "linux" and f.get("arch") == "amd64" and f.get("kind") == "archive":
            return version, f"https://go.dev/dl/{f['filename']}", int(f.get("size", 0))
    raise RuntimeError(f"No linux-amd64 archive found in Go release {version}")


def resolve_node() -> Tuple[str, str, int]:
    releases = fetch_json("https://nodejs.org/dist/index.json")
    latest_lts = next((r for r in releases if r.get("lts")), releases[0])
    version = latest_lts["version"]
    return version, f"https://nodejs.org/dist/{version}/node-{version}-linux-x64.tar.xz", 0


def install_neovim_source(pkg: Pkg, force: bool, state: Dict[str, str]) -> Optional[str]:
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

    need_build = force or not is_neovim_installed(pkg)

    if not src_dir.exists():
        print(f"[{pkg.name}] Cloning neovim/neovim to {src_dir}...")
        src_dir.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "clone", "https://github.com/neovim/neovim.git", str(src_dir)], check=True
        )
        need_build = True
    else:
        print(f"[{pkg.name}] Updating repository in {src_dir}...")
        subprocess.run(["git", "checkout", "master"], cwd=src_dir, check=True)
        old_head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=src_dir, text=True
        ).strip()
        subprocess.run(["git", "pull", "--rebase"], cwd=src_dir, check=True)
        new_head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=src_dir, text=True
        ).strip()
        if old_head != new_head:
            need_build = True

    if not need_build:
        ver = state.get(pkg.name, "installed (source)")
        print(f"[{pkg.name}] Already up to date ({ver})")
        return None

    print(
        f"[{pkg.name}] Building Neovim with "
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

    try:
        ver_line = subprocess.check_output([str(nvim_bin), "--version"], text=True).splitlines()[0]
        return ver_line.split()[1]
    except Exception:
        return "source"


def remove_neovim_source(pkg: Pkg) -> None:
    unlink_bins(pkg.name, ["nvim"])
    dest_prefix = LOCAL_DIR / "nvim"
    if dest_prefix.exists():
        shutil.rmtree(dest_prefix)
        print(f"[{pkg.name}] Removed directory {dest_prefix}")


def is_neovim_installed(_pkg: Pkg) -> bool:
    return (LOCAL_DIR / "nvim" / "bin" / "nvim").exists() and (BIN_DIR / "nvim").exists()


def install_rustup(pkg: Pkg, force: bool, state: Dict[str, str]) -> Optional[str]:
    cargo_dir = Path.home() / ".cargo" / "bin"
    rustup_bin = cargo_dir / "rustup"
    rustc_bin = cargo_dir / "rustc"

    if is_rust_installed(pkg) and rustup_bin.exists():
        if force:
            print(f"[{pkg.name}] Updating toolchain via rustup...")
            subprocess.run([str(rustup_bin), "update"], check=True)
        else:
            ver = state.get(pkg.name, "installed")
            print(f"[{pkg.name}] Already installed ({ver})")
            return None
    else:
        print(f"[{pkg.name}] Installing rustup and cargo to ~/.cargo...")
        with http_get("https://sh.rustup.rs") as resp:
            installer = resp.read()
        subprocess.run(
            ["sh", "-s", "--", "-y", "--no-modify-path"],
            input=installer,
            check=True,
        )

    if rustc_bin.exists():
        out = subprocess.check_output([str(rustc_bin), "--version"], text=True).strip()
        parts = out.split()
        return parts[1] if len(parts) > 1 else "installed"
    return "installed"


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

OLD_GLIBC = glibc_version() < (2, 32)

PACKAGES = [
    # --- Default Core Packages ---
    Pkg(
        "nvim",
        default=True,
        desc="Neovim editor (built from source into ~/.local/nvim)",
        source=Custom(
            install=install_neovim_source,
            remove=remove_neovim_source,
            is_installed=is_neovim_installed,
        ),
    ),
    Pkg(
        "nvim-bin",
        desc="Neovim editor (prebuilt binary)",
        source=GitHubRelease(
            repo="neovim/neovim-releases" if OLD_GLIBC else "neovim/neovim",
            asset="nvim-linux-x86_64.tar.gz",
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
        ),
    ),
    # --- Optional Packages (LSPs, Runtimes, Tools) ---
    Pkg(
        "tree-sitter",
        desc="tree-sitter CLI (built from source via cargo)",
        source=CargoInstall(crate="tree-sitter-cli", bins=["tree-sitter"]),
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
            asset=(
                "slang-server-old-linux-x64-gcc.tar.gz"
                if OLD_GLIBC
                else "slang-server-linux-x64.tar.gz"
            ),
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
            package="github.com/isaacphi/mcp-language-server@latest",
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
]


if __name__ == "__main__":
    run_cli(PACKAGES)

