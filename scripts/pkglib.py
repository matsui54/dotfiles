#!/usr/bin/env python3
"""
Core library for user-space package management (~/.local).
Provides reusable Installer building blocks and CLI runner,
completely decoupled from specific package definitions.
"""

from abc import ABC, abstractmethod
import argparse
from dataclasses import dataclass, field
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
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple, Union
import urllib.request
import zipfile

LOCAL_DIR = Path.home() / ".local"
OPT_DIR = LOCAL_DIR / "opt"
BIN_DIR = LOCAL_DIR / "bin"
SRC_DIR = LOCAL_DIR / "src"
STATE_FILE = OPT_DIR / ".pkg_state.json"

StrOrCallable = Union[str, Callable[[], str]]


def glibc_version() -> Tuple[int, int]:
    """Return host glibc version as (major, minor), or (2, 35) as fallback."""
    try:
        ver_str = os.confstr("CS_GNU_LIBC_VERSION")
        if ver_str:
            parts = ver_str.split()[-1].split(".")
            return (int(parts[0]), int(parts[1]))
    except Exception:
        pass
    return (2, 35)


def eval_str(val: StrOrCallable) -> str:
    return val() if callable(val) else val


def parse_bin_spec(b: str) -> Tuple[str, str]:
    """Parse 'link_name:rel_target' or 'rel_target' into (link_name, rel_target)."""
    if ":" in b:
        link_name, rel_target = b.split(":", 1)
        return link_name, rel_target
    return Path(b).name, b


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


def http_get(url: str, is_api: bool = False):
    headers = {"User-Agent": "dotfiles-pkg-manager/2.0"}
    if is_api:
        headers["Accept"] = "application/vnd.github+json"
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req)


def fetch_json(url: str, is_api: bool = False) -> Any:
    with http_get(url, is_api=is_api) as resp:
        return json.loads(resp.read().decode("utf-8"))


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


def extract_archive(
    data: bytes, url: str, dest_dir: Path, strip: bool, bins: Sequence[str]
) -> None:
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
        raw = gzip.decompress(data)
        _, rel_target = parse_bin_spec(bins[0])
        target = dest_dir / rel_target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        target.chmod(0o755)

    else:
        raise RuntimeError(f"Unsupported archive format: {url}")


def link_executable(src_bin: Path, link_name: str) -> Path:
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    src_bin.chmod(src_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    link_path = BIN_DIR / link_name
    if link_path.exists() or link_path.is_symlink():
        link_path.unlink()
    link_path.symlink_to(src_bin)
    print(f"  Linked {link_path} -> {src_bin}")
    return link_path


def unlink_bins(pkg_name: str, bins: Sequence[str]) -> None:
    for b in bins:
        link_name, _ = parse_bin_spec(b)
        link_path = BIN_DIR / link_name
        if link_path.is_symlink() or link_path.exists():
            link_path.unlink()
            print(f"[{pkg_name}] Removed {link_path}")


# ============================================================================
# Installer Interfaces & Standard Implementations
# ============================================================================


class Installer(ABC):
    """Base interface for all package installation strategies."""

    depends: Sequence[str] = ()

    @abstractmethod
    def install(self, pkg: "Pkg", force: bool, state: Dict[str, str]) -> Optional[str]:
        """Install or update package. Return version string if updated, or None if skipped."""

    @abstractmethod
    def remove(self, pkg: "Pkg") -> None:
        """Remove installed files and symlinks."""

    @abstractmethod
    def is_installed(self, pkg: "Pkg") -> bool:
        """Return True if package binaries are present on disk."""


class ArchiveInstaller(Installer):
    """Base installer for packages downloaded as archives into ~/.local/opt/<name>."""

    def __init__(self, bins: Sequence[str], strip: bool = True, depends: Sequence[str] = ()):
        self.bins = list(bins)
        self.strip = strip
        self.depends = list(depends)

    @abstractmethod
    def resolve(self) -> Tuple[str, str, int]:
        """Return (version, download_url, expected_size)."""

    def is_installed(self, pkg: "Pkg") -> bool:
        dest_dir = OPT_DIR / pkg.name
        return dest_dir.exists() and all(
            (BIN_DIR / parse_bin_spec(b)[0]).exists() for b in self.bins
        )

    def install(self, pkg: "Pkg", force: bool, state: Dict[str, str]) -> Optional[str]:
        dest_dir = OPT_DIR / pkg.name
        print(f"[{pkg.name}] Checking latest version...")
        version, url, size = self.resolve()
        installed_ver = state.get(pkg.name)

        if not force and installed_ver == version and self.is_installed(pkg):
            print(f"[{pkg.name}] Already up to date ({version})")
            return None

        print(f"[{pkg.name}] Installing {version} from {url}")
        data = download_bytes(url, size)
        print(f"  Extracting to {dest_dir}...")
        extract_archive(data, url, dest_dir, self.strip, self.bins)

        for b in self.bins:
            link_name, rel_target = parse_bin_spec(b)
            src_bin = dest_dir / rel_target
            if not src_bin.exists():
                matches = [
                    p
                    for p in dest_dir.rglob(Path(rel_target).name)
                    if p.is_file() and not p.is_symlink()
                ]
                if matches:
                    src_bin = matches[0]
                else:
                    raise RuntimeError(f"Expected binary not found after extraction: {src_bin}")
            link_executable(src_bin, link_name)

        return version

    def remove(self, pkg: "Pkg") -> None:
        unlink_bins(pkg.name, self.bins)
        dest_dir = OPT_DIR / pkg.name
        if dest_dir.exists():
            shutil.rmtree(dest_dir)
            print(f"[{pkg.name}] Removed directory {dest_dir}")


class GitHubRelease(ArchiveInstaller):
    """Install prebuilt archive from GitHub Releases."""

    def __init__(
        self,
        repo: StrOrCallable,
        asset: StrOrCallable,
        bins: Sequence[str],
        strip: bool = True,
        depends: Sequence[str] = (),
    ):
        super().__init__(bins=bins, strip=strip, depends=depends)
        self.repo = repo
        self.asset = asset

    def resolve(self) -> Tuple[str, str, int]:
        repo = eval_str(self.repo)
        asset_pattern = eval_str(self.asset)
        data = fetch_json(f"https://api.github.com/repos/{repo}/releases/latest", is_api=True)
        tag = data["tag_name"]
        for asset in data.get("assets", []):
            if fnmatch.fnmatch(asset["name"], asset_pattern):
                return tag, asset["browser_download_url"], int(asset.get("size", 0))
        available = [a["name"] for a in data.get("assets", [])]
        raise RuntimeError(
            f"No asset matching '{asset_pattern}' in {repo}@{tag}. Available: {available}"
        )


class UrlArchive(ArchiveInstaller):
    """Install archive resolved via custom URL resolver function."""

    def __init__(
        self,
        resolver: Callable[[], Tuple[str, str, int]],
        bins: Sequence[str],
        strip: bool = True,
        depends: Sequence[str] = (),
    ):
        super().__init__(bins=bins, strip=strip, depends=depends)
        self._resolver = resolver

    def resolve(self) -> Tuple[str, str, int]:
        return self._resolver()


class NpmPackage(ArchiveInstaller):
    """Install bundled npm package tarball directly from registry.npmjs.org."""

    def __init__(
        self,
        package: str,
        bins: Sequence[str],
        node_pkg: str = "node",
    ):
        super().__init__(bins=bins, strip=True, depends=[node_pkg] if node_pkg else [])
        self.package = package

    def resolve(self) -> Tuple[str, str, int]:
        data = fetch_json(f"https://registry.npmjs.org/{self.package}/latest")
        return data["version"], data["dist"]["tarball"], 0


class GoInstall(Installer):
    """Install Go binary via `GOBIN=~/.local/bin go install <package>`."""

    def __init__(self, package: str, bins: Sequence[str], go_pkg: str = "go"):
        self.package = package
        self.bins = list(bins)
        self.depends = [go_pkg] if go_pkg else []

    def is_installed(self, pkg: "Pkg") -> bool:
        return all((BIN_DIR / parse_bin_spec(b)[0]).exists() for b in self.bins)

    def install(self, pkg: "Pkg", force: bool, state: Dict[str, str]) -> Optional[str]:
        go_bin = BIN_DIR / "go"
        if not go_bin.exists():
            which_go = shutil.which("go")
            if which_go:
                go_bin = Path(which_go)
            else:
                raise RuntimeError("Go compiler not found. Please install go first.")

        installed_ver = state.get(pkg.name)
        if not force and installed_ver and self.is_installed(pkg):
            print(f"[{pkg.name}] Already installed ({installed_ver})")
            return None

        print(f"[{pkg.name}] Installing {self.package} via go install...")
        BIN_DIR.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        env["GOBIN"] = str(BIN_DIR)
        env["PATH"] = f"{BIN_DIR}:{env.get('PATH', '')}"
        subprocess.run([str(go_bin), "install", self.package], env=env, check=True)

        bin_path = BIN_DIR / parse_bin_spec(self.bins[0])[0]
        ver = "installed"
        try:
            out = subprocess.check_output([str(go_bin), "version", "-m", str(bin_path)], text=True)
            for line in out.splitlines():
                parts = line.strip().split()
                if len(parts) >= 3 and parts[0] == "mod":
                    ver = parts[2]
                    break
        except Exception:
            pass
        return ver

    def remove(self, pkg: "Pkg") -> None:
        unlink_bins(pkg.name, self.bins)


class CargoInstall(Installer):
    """Build and install Rust crate via `cargo install`."""

    def __init__(
        self,
        crate: str,
        bins: Sequence[str],
        locked: bool = True,
        rust_pkg: str = "rust",
    ):
        self.crate = crate
        self.bins = list(bins)
        self.locked = locked
        self.depends = [rust_pkg] if rust_pkg else []

    def is_installed(self, pkg: "Pkg") -> bool:
        return all((BIN_DIR / parse_bin_spec(b)[0]).exists() for b in self.bins)

    def install(self, pkg: "Pkg", force: bool, state: Dict[str, str]) -> Optional[str]:
        cargo_bin = Path.home() / ".cargo" / "bin" / "cargo"
        if not cargo_bin.exists():
            which_cargo = shutil.which("cargo")
            if which_cargo:
                cargo_bin = Path(which_cargo)
            else:
                raise RuntimeError("Cargo not found. Please install rust first.")

        installed_ver = state.get(pkg.name)
        if not force and installed_ver and self.is_installed(pkg):
            print(f"[{pkg.name}] Already installed ({installed_ver})")
            return None

        cmd = [str(cargo_bin), "install"]
        if self.locked:
            cmd.append("--locked")
        cmd.append(self.crate)

        print(f"[{pkg.name}] Building and installing {self.crate} via cargo install...")
        env = os.environ.copy()
        env["PATH"] = f"{BIN_DIR}:{Path.home() / '.cargo' / 'bin'}:{env.get('PATH', '')}"
        subprocess.run(cmd, env=env, check=True)

        for b in self.bins:
            link_name, _ = parse_bin_spec(b)
            cargo_target = Path.home() / ".cargo" / "bin" / link_name
            if cargo_target.exists():
                link_executable(cargo_target, link_name)

        bin_path = BIN_DIR / parse_bin_spec(self.bins[0])[0]
        ver = "installed"
        if bin_path.exists():
            try:
                out = subprocess.check_output([str(bin_path), "--version"], text=True).strip()
                parts = out.split()
                if len(parts) >= 2:
                    ver = parts[1]
            except Exception:
                pass
        return ver

    def remove(self, pkg: "Pkg") -> None:
        unlink_bins(pkg.name, self.bins)
        for b in self.bins:
            link_name, _ = parse_bin_spec(b)
            cargo_bin_path = Path.home() / ".cargo" / "bin" / link_name
            if cargo_bin_path.exists():
                cargo_bin_path.unlink()
                print(f"[{pkg.name}] Removed {cargo_bin_path}")


class UvTool(Installer):
    """Install Python CLI tool via `uv tool install`."""

    def __init__(
        self,
        package: str,
        bins: Sequence[str],
        python: Optional[str] = None,
        uv_pkg: str = "uv",
    ):
        self.package = package
        self.bins = list(bins)
        self.python = python
        self.depends = [uv_pkg] if uv_pkg else []

    def _find_uv(self) -> Path:
        uv_bin = BIN_DIR / "uv"
        if uv_bin.exists():
            return uv_bin
        which_uv = shutil.which("uv")
        if which_uv:
            return Path(which_uv)
        raise RuntimeError("uv not found. Please install uv first.")

    def is_installed(self, pkg: "Pkg") -> bool:
        return all((BIN_DIR / parse_bin_spec(b)[0]).exists() for b in self.bins)

    def install(self, pkg: "Pkg", force: bool, state: Dict[str, str]) -> Optional[str]:
        uv_bin = self._find_uv()
        installed_ver = state.get(pkg.name)
        if not force and installed_ver and self.is_installed(pkg):
            print(f"[{pkg.name}] Already installed ({installed_ver})")
            return None

        cmd = [str(uv_bin), "tool", "install"]
        if force:
            cmd.append("--upgrade")
        if self.python:
            cmd.extend(["-p", self.python])
        cmd.append(self.package)

        print(f"[{pkg.name}] Installing {self.package} via uv tool install...")
        BIN_DIR.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        env["UV_TOOL_BIN_DIR"] = str(BIN_DIR)
        env["PATH"] = f"{BIN_DIR}:{env.get('PATH', '')}"
        subprocess.run(cmd, env=env, check=True)

        ver = "installed"
        try:
            out = subprocess.check_output([str(uv_bin), "tool", "list"], env=env, text=True)
            for line in out.splitlines():
                parts = line.strip().split()
                if len(parts) >= 2 and parts[0] == self.package:
                    ver = parts[1]
                    break
        except Exception:
            pass
        return ver

    def remove(self, pkg: "Pkg") -> None:
        try:
            uv_bin = self._find_uv()
            env = os.environ.copy()
            env["UV_TOOL_BIN_DIR"] = str(BIN_DIR)
            subprocess.run([str(uv_bin), "tool", "uninstall", self.package], env=env, check=True)
        except Exception:
            unlink_bins(pkg.name, self.bins)


class Custom(Installer):
    """Custom callback-driven installer for specialized builds/toolchains."""

    def __init__(
        self,
        install: Callable[["Pkg", bool, Dict[str, str]], Optional[str]],
        remove: Callable[["Pkg"], None],
        is_installed: Callable[["Pkg"], bool],
        depends: Sequence[str] = (),
    ):
        self._install = install
        self._remove = remove
        self._is_installed = is_installed
        self.depends = list(depends)

    def install(self, pkg: "Pkg", force: bool, state: Dict[str, str]) -> Optional[str]:
        return self._install(pkg, force, state)

    def remove(self, pkg: "Pkg") -> None:
        self._remove(pkg)

    def is_installed(self, pkg: "Pkg") -> bool:
        return self._is_installed(pkg)


# ============================================================================
# Package Model & CLI Runner
# ============================================================================


@dataclass
class Pkg:
    name: str
    source: Installer
    desc: str = ""
    default: bool = False
    depends: List[str] = field(default_factory=list)

    @property
    def all_depends(self) -> List[str]:
        deps: List[str] = []
        for d in list(self.source.depends) + self.depends:
            if d not in deps:
                deps.append(d)
        return deps


class PackageManager:
    def __init__(self, packages: Sequence[Pkg]):
        self.packages: Dict[str, Pkg] = {p.name: p for p in packages}

    def install(self, name: str, force: bool = False) -> None:
        if name not in self.packages:
            raise ValueError(f"Unknown package: {name}")
        pkg = self.packages[name]

        for dep in pkg.all_depends:
            self.install(dep, force=False)

        state = load_state()
        new_version = pkg.source.install(pkg, force=force, state=state)
        if new_version is not None:
            state = load_state()
            state[name] = new_version
            save_state(state)
            print(f"[{name}] Done ({new_version})")

    def remove(self, name: str) -> None:
        if name not in self.packages:
            raise ValueError(f"Unknown package: {name}")
        pkg = self.packages[name]
        pkg.source.remove(pkg)
        state = load_state()
        if name in state:
            del state[name]
            save_state(state)

    def list_packages(self) -> None:
        state = load_state()
        print(f"{'PACKAGE':<22} {'DEFAULT':<9} {'INSTALLED':<16} {'DESCRIPTION'}")
        print("-" * 78)
        for name, pkg in self.packages.items():
            is_def = "yes" if pkg.default else "no"
            ver = state.get(name, "-")
            bins_ok = pkg.source.is_installed(pkg)
            if ver != "-" and not bins_ok:
                ver = f"{ver} (broken)"
            elif ver == "-" and bins_ok:
                ver = "installed"
            print(f"{name:<22} {is_def:<9} {ver:<16} {pkg.desc}")


def run_cli(packages: Sequence[Pkg]) -> None:
    pm = PackageManager(packages)
    parser = argparse.ArgumentParser(
        description="Lightweight user-space package manager (~/.local)"
    )
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("list", aliases=["status", "ls"], help="List packages and installation status")

    p_install = sub.add_parser(
        "install", aliases=["update", "up", "i"], help="Install or update packages"
    )
    p_install.add_argument(
        "packages", nargs="*", help="Package names (default: all default packages)"
    )
    p_install.add_argument(
        "-a", "--all", action="store_true", help="Install all packages including optional ones"
    )
    p_install.add_argument(
        "-f", "--force", action="store_true", help="Force reinstall even if up to date"
    )

    p_remove = sub.add_parser("remove", aliases=["rm", "uninstall"], help="Remove packages")
    p_remove.add_argument("packages", nargs="+", help="Package names to remove")

    args = parser.parse_args()

    if not args.cmd or args.cmd in ("list", "status", "ls"):
        pm.list_packages()
        return

    if args.cmd in ("install", "update", "up", "i"):
        if args.all:
            targets = list(pm.packages.keys())
        elif args.packages:
            targets = args.packages
        else:
            targets = [name for name, p in pm.packages.items() if p.default]

        failed = []
        for name in targets:
            try:
                pm.install(name, force=args.force)
            except Exception as e:
                print(f"[{name}] ERROR: {e}", file=sys.stderr)
                failed.append(name)
        if failed:
            sys.exit(1)

    elif args.cmd in ("remove", "rm", "uninstall"):
        for name in args.packages:
            pm.remove(name)

