#!/usr/bin/env python3
"""
Core library for user-space package management (~/.local).
Provides reusable Installer building blocks, lockfile verification, and CLI runner,
completely decoupled from specific package definitions.
"""

from abc import ABC, abstractmethod
import argparse
from dataclasses import dataclass, field
import fnmatch
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple, Union
import urllib.parse
import urllib.request
import zipfile

LOCAL_DIR = Path.home() / ".local"
OPT_DIR = LOCAL_DIR / "opt"
BIN_DIR = LOCAL_DIR / "bin"
SRC_DIR = LOCAL_DIR / "src"
STATE_FILE = OPT_DIR / ".pkg_state.json"
LOCK_FILE = Path(__file__).resolve().parent / "pkg-lock.json"

StrOrCallable = Union[str, Callable[[], str]]


@dataclass
class ArchiveSpec:
    version: str
    url: str
    size: int = 0
    sha256: Optional[str] = None


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


def is_old_glibc() -> bool:
    return glibc_version() < (2, 32)


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
    OPT_DIR.chmod(0o755)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    STATE_FILE.chmod(0o644)


def load_lock(lock_path: Path = LOCK_FILE) -> Dict[str, Dict[str, Any]]:
    if lock_path.exists():
        try:
            return json.loads(lock_path.read_text(encoding="utf-8"))
        except Exception as e:
            raise RuntimeError(f"Failed to parse lockfile {lock_path}: {e}") from e
    return {}


def save_lock(lock_data: Dict[str, Dict[str, Any]], lock_path: Path = LOCK_FILE) -> None:
    lock_path.write_text(
        json.dumps(lock_data, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def http_get(url: str, is_api: bool = False):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https":
        raise RuntimeError(f"Refusing non-HTTPS URL: {url}")
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
                print(
                    f"\r  Downloading... {pct:5.1f}% ({downloaded // 1024} KB)",
                    end="",
                    flush=True,
                )
            else:
                print(f"\r  Downloading... {downloaded // 1024} KB", end="", flush=True)
    print()
    return buf.getvalue()


def compute_sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify_sha256(data: bytes, expected_sha256: str, pkg_name: str) -> None:
    if not expected_sha256:
        raise RuntimeError(f"[{pkg_name}] Missing expected SHA256 checksum in lock entry")
    actual = compute_sha256_bytes(data)
    if actual.lower() != expected_sha256.lower():
        raise RuntimeError(
            f"[{pkg_name}] SHA256 verification failed!\n"
            f"  Expected: {expected_sha256.lower()}\n"
            f"  Actual:   {actual.lower()}"
        )


def resolve_spec_to_lock_dict(spec: ArchiveSpec, pkg_name: str) -> Dict[str, Any]:
    sha256 = spec.sha256
    size = spec.size
    if not sha256:
        print(f"[{pkg_name}] Downloading {spec.url} to compute SHA256...")
        data = download_bytes(spec.url, spec.size)
        sha256 = compute_sha256_bytes(data)
        size = len(data)
    return {
        "version": spec.version,
        "url": spec.url,
        "sha256": sha256.lower(),
        "size": size,
    }


def _sanitize_mode(mode: int, default_exec: bool = False) -> int:
    """Strip SUID/SGID/sticky and group/other write bits; return 0o755 or 0o644."""
    if default_exec or (mode & 0o111):
        return 0o755
    return 0o644


def _safe_extract_path(dest_dir: Path, raw_name: str, strip: bool) -> Optional[Path]:
    """Validate and resolve archive member path within dest_dir to prevent path traversal."""
    pos_path = PurePosixPath(raw_name)
    if pos_path.is_absolute() or raw_name.startswith(("/", "\\")):
        raise RuntimeError(f"Unsafe absolute path in archive: {raw_name}")

    parts = [p for p in pos_path.parts if p not in ("", "/", ".")]
    if any(p == ".." for p in parts):
        raise RuntimeError(f"Unsafe '..' path traversal in archive: {raw_name}")

    if strip:
        if len(parts) <= 1:
            return None
        rel_path = Path(*parts[1:])
    else:
        if not parts:
            return None
        rel_path = Path(*parts)

    dest_resolved = dest_dir.resolve()
    target = dest_resolved / rel_path

    # Check lexical containment first
    norm_target = Path(os.path.normpath(str(target)))
    if not norm_target.is_relative_to(dest_resolved):
        raise RuntimeError(f"Archive path escapes destination directory: {raw_name}")

    # Check parent realpath containment (prevents writing through an earlier symlink)
    if target.parent.exists() and not target.parent.resolve().is_relative_to(dest_resolved):
        raise RuntimeError(f"Archive parent resolves outside destination directory: {raw_name}")

    return target


def _validate_symlink_target(dest_dir: Path, link_path: Path, linkname: str) -> None:
    """Ensure symlink target does not point outside dest_dir."""
    if Path(linkname).is_absolute() or linkname.startswith(("/", "\\")):
        raise RuntimeError(f"Unsafe absolute symlink in archive: {link_path.name} -> {linkname}")
    dest_resolved = dest_dir.resolve()
    combined = Path(os.path.normpath(str(link_path.parent / linkname)))
    if not combined.is_relative_to(dest_resolved):
        raise RuntimeError(
            f"Unsafe symlink escaping destination directory: {link_path.name} -> {linkname}"
        )


def extract_archive(
    data: bytes, url: str, dest_dir: Path, strip: bool, bins: Sequence[str]
) -> None:
    if dest_dir.exists():
        shutil.rmtree(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_dir.chmod(0o755)

    lower_url = url.lower()
    if lower_url.endswith((".tar.gz", ".tgz", ".tar.xz", ".txz")):
        mode = "r:xz" if lower_url.endswith((".tar.xz", ".txz")) else "r:gz"
        with tarfile.open(fileobj=io.BytesIO(data), mode=mode) as tar:
            for member in tar.getmembers():
                target = _safe_extract_path(dest_dir, member.name, strip)
                if target is None:
                    continue

                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    target.chmod(0o755)
                elif member.issym():
                    _validate_symlink_target(dest_dir, target, member.linkname)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    target.symlink_to(member.linkname)
                elif member.islnk():
                    link_target = _safe_extract_path(dest_dir, member.linkname, strip)
                    if link_target is None or not link_target.exists():
                        raise RuntimeError(
                            f"Invalid hardlink in archive: {member.name} -> {member.linkname}"
                        )
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    os.link(link_target, target)
                elif member.isfile():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    f = tar.extractfile(member)
                    if f is not None:
                        target.write_bytes(f.read())
                        target.chmod(_sanitize_mode(member.mode))
                else:
                    raise RuntimeError(
                        f"Unsupported special file type in archive: {member.name}"
                    )

    elif lower_url.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            for info in zf.infolist():
                target = _safe_extract_path(dest_dir, info.filename, strip)
                if target is None:
                    continue

                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    target.chmod(0o755)
                else:
                    perm = (info.external_attr >> 16) & 0o777777
                    # Check if entry is a symlink (S_IFLNK = 0o120000)
                    if (perm & 0o170000) == 0o120000:
                        linkname = zf.read(info.filename).decode("utf-8")
                        _validate_symlink_target(dest_dir, target, linkname)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        if target.exists() or target.is_symlink():
                            target.unlink()
                        target.symlink_to(linkname)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(zf.read(info.filename))
                        target.chmod(_sanitize_mode(perm & 0o777))

    elif lower_url.endswith(".gz"):
        raw = gzip.decompress(data)
        _, rel_target = parse_bin_spec(bins[0])
        target = _safe_extract_path(dest_dir, rel_target, strip=False)
        if target is None:
            raise RuntimeError(f"Invalid binary target for .gz archive: {rel_target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        target.chmod(0o755)

    else:
        raise RuntimeError(f"Unsupported archive format: {url}")


def link_executable(src_bin: Path, link_name: str) -> Path:
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    BIN_DIR.chmod(0o755)
    src_bin.chmod(0o755)
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
    def lock(self, pkg: "Pkg") -> Dict[str, Any]:
        """Resolve latest version/URL/checksums and return lock metadata dict."""

    @abstractmethod
    def install(
        self,
        pkg: "Pkg",
        force: bool,
        state: Dict[str, str],
        lock_entry: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
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
    def resolve_spec(self) -> ArchiveSpec:
        """Return ArchiveSpec(version, url, size, sha256)."""

    def is_installed(self, pkg: "Pkg") -> bool:
        dest_dir = OPT_DIR / pkg.name
        return dest_dir.exists() and all(
            (BIN_DIR / parse_bin_spec(b)[0]).exists() for b in self.bins
        )

    def lock(self, pkg: "Pkg") -> Dict[str, Any]:
        spec = self.resolve_spec()
        return resolve_spec_to_lock_dict(spec, pkg.name)

    def _select_lock_variant(self, lock_entry: Dict[str, Any]) -> Dict[str, Any]:
        if is_old_glibc() and "old_glibc" in lock_entry:
            return lock_entry["old_glibc"]
        return lock_entry

    def _find_binary(self, base_dir: Path, rel_target: str) -> Path:
        src_bin = base_dir / rel_target
        if src_bin.exists():
            return src_bin
        matches = [
            p
            for p in base_dir.rglob(Path(rel_target).name)
            if p.is_file() and not p.is_symlink()
        ]
        if matches:
            return matches[0]
        raise RuntimeError(f"Expected binary not found after extraction: {src_bin}")

    def install(
        self,
        pkg: "Pkg",
        force: bool,
        state: Dict[str, str],
        lock_entry: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
        dest_dir = OPT_DIR / pkg.name
        if lock_entry is not None:
            active = self._select_lock_variant(lock_entry)
            version = active["version"]
            url = active["url"]
            expected_sha256 = active["sha256"]
            size = int(active.get("size", 0))
        else:
            print(f"[{pkg.name}] Resolving latest version (unlocked)...")
            spec = self.resolve_spec()
            version = spec.version
            url = spec.url
            expected_sha256 = spec.sha256
            size = spec.size

        installed_ver = state.get(pkg.name)
        if not force and installed_ver == version and self.is_installed(pkg):
            print(f"[{pkg.name}] Already up to date ({version})")
            return None

        print(f"[{pkg.name}] Installing {version} from {url}")
        data = download_bytes(url, size)
        if expected_sha256:
            verify_sha256(data, expected_sha256, pkg.name)
            print(f"  Verified SHA256: {expected_sha256[:16]}...")

        OPT_DIR.mkdir(parents=True, exist_ok=True)
        OPT_DIR.chmod(0o755)
        tmp_dir = OPT_DIR / f".tmp_{pkg.name}_{os.getpid()}"
        try:
            print(f"  Extracting safely to {dest_dir}...")
            extract_archive(data, url, tmp_dir, self.strip, self.bins)
            # Validate all binaries exist inside tmp_dir before replacing dest_dir
            for b in self.bins:
                _, rel_target = parse_bin_spec(b)
                self._find_binary(tmp_dir, rel_target)

            if dest_dir.exists():
                shutil.rmtree(dest_dir)
            tmp_dir.rename(dest_dir)
        finally:
            if tmp_dir.exists():
                shutil.rmtree(tmp_dir, ignore_errors=True)

        for b in self.bins:
            link_name, rel_target = parse_bin_spec(b)
            src_bin = self._find_binary(dest_dir, rel_target)
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
        old_glibc_repo: Optional[str] = None,
        old_glibc_asset: Optional[str] = None,
    ):
        super().__init__(bins=bins, strip=strip, depends=depends)
        self.repo = repo
        self.asset = asset
        self.old_glibc_repo = old_glibc_repo
        self.old_glibc_asset = old_glibc_asset

    def _resolve_github_asset(self, repo: str, asset_pattern: str) -> ArchiveSpec:
        data = fetch_json(f"https://api.github.com/repos/{repo}/releases/latest", is_api=True)
        tag = data["tag_name"]
        for asset in data.get("assets", []):
            if fnmatch.fnmatch(asset["name"], asset_pattern):
                sha256 = None
                digest = asset.get("digest")
                if isinstance(digest, str) and digest.startswith("sha256:"):
                    sha256 = digest.split(":", 1)[1]
                return ArchiveSpec(
                    version=tag,
                    url=asset["browser_download_url"],
                    size=int(asset.get("size", 0)),
                    sha256=sha256,
                )
        available = [a["name"] for a in data.get("assets", [])]
        raise RuntimeError(
            f"No asset matching '{asset_pattern}' in {repo}@{tag}. Available: {available}"
        )

    def resolve_spec(self) -> ArchiveSpec:
        if is_old_glibc() and (self.old_glibc_repo or self.old_glibc_asset):
            repo = self.old_glibc_repo or eval_str(self.repo)
            asset_pattern = self.old_glibc_asset or eval_str(self.asset)
        else:
            repo = eval_str(self.repo)
            asset_pattern = eval_str(self.asset)
        return self._resolve_github_asset(repo, asset_pattern)

    def lock(self, pkg: "Pkg") -> Dict[str, Any]:
        default_spec = self._resolve_github_asset(eval_str(self.repo), eval_str(self.asset))
        entry = resolve_spec_to_lock_dict(default_spec, pkg.name)
        if self.old_glibc_repo or self.old_glibc_asset:
            old_repo = self.old_glibc_repo or eval_str(self.repo)
            old_asset = self.old_glibc_asset or eval_str(self.asset)
            old_spec = self._resolve_github_asset(old_repo, old_asset)
            entry["old_glibc"] = resolve_spec_to_lock_dict(old_spec, f"{pkg.name} (old_glibc)")
        return entry


class UrlArchive(ArchiveInstaller):
    """Install archive resolved via custom URL resolver function."""

    def __init__(
        self,
        resolver: Callable[[], ArchiveSpec],
        bins: Sequence[str],
        strip: bool = True,
        depends: Sequence[str] = (),
    ):
        super().__init__(bins=bins, strip=strip, depends=depends)
        self._resolver = resolver

    def resolve_spec(self) -> ArchiveSpec:
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

    def resolve_spec(self) -> ArchiveSpec:
        data = fetch_json(f"https://registry.npmjs.org/{self.package}/latest")
        return ArchiveSpec(
            version=data["version"],
            url=data["dist"]["tarball"],
            size=0,
            sha256=None,
        )


class GoInstall(Installer):
    """Install Go binary via `GOBIN=~/.local/bin go install <package>@<version>`."""

    def __init__(self, package: str, bins: Sequence[str], go_pkg: str = "go"):
        # Strip trailing @latest if specified so we can append exact version
        self.package = package.split("@")[0]
        self.bins = list(bins)
        self.depends = [go_pkg] if go_pkg else []

    def is_installed(self, pkg: "Pkg") -> bool:
        return all((BIN_DIR / parse_bin_spec(b)[0]).exists() for b in self.bins)

    def lock(self, _pkg: "Pkg") -> Dict[str, Any]:
        info = fetch_json(f"https://proxy.golang.org/{self.package}/@latest")
        return {"version": info["Version"]}

    def install(
        self,
        pkg: "Pkg",
        force: bool,
        state: Dict[str, str],
        lock_entry: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
        go_bin = BIN_DIR / "go"
        if not go_bin.exists():
            which_go = shutil.which("go")
            if which_go:
                go_bin = Path(which_go)
            else:
                raise RuntimeError("Go compiler not found. Please install go first.")

        target_ver = lock_entry["version"] if lock_entry else "latest"
        installed_ver = state.get(pkg.name)
        if not force and installed_ver == target_ver and self.is_installed(pkg):
            print(f"[{pkg.name}] Already up to date ({installed_ver})")
            return None

        pkg_spec = f"{self.package}@{target_ver}"
        print(f"[{pkg.name}] Installing {pkg_spec} via go install...")
        BIN_DIR.mkdir(parents=True, exist_ok=True)
        BIN_DIR.chmod(0o755)
        env = os.environ.copy()
        env["GOBIN"] = str(BIN_DIR)
        env["PATH"] = f"{BIN_DIR}:{env.get('PATH', '')}"
        subprocess.run([str(go_bin), "install", pkg_spec], env=env, check=True)

        return target_ver

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

    def lock(self, _pkg: "Pkg") -> Dict[str, Any]:
        data = fetch_json(f"https://crates.io/api/v1/crates/{self.crate}")
        crate_info = data["crate"]
        ver = crate_info.get("max_stable_version") or crate_info["max_version"]
        return {"version": ver}

    def install(
        self,
        pkg: "Pkg",
        force: bool,
        state: Dict[str, str],
        lock_entry: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
        cargo_bin = Path.home() / ".cargo" / "bin" / "cargo"
        if not cargo_bin.exists():
            which_cargo = shutil.which("cargo")
            if which_cargo:
                cargo_bin = Path(which_cargo)
            else:
                raise RuntimeError("Cargo not found. Please install rust first.")

        target_ver = lock_entry["version"] if lock_entry else None
        installed_ver = state.get(pkg.name)
        if not force and installed_ver and (target_ver is None or installed_ver == target_ver) and self.is_installed(pkg):
            print(f"[{pkg.name}] Already up to date ({installed_ver})")
            return None

        cmd = [str(cargo_bin), "install"]
        if self.locked:
            cmd.append("--locked")
        if target_ver:
            cmd.extend(["--version", target_ver])
        if force:
            cmd.append("--force")
        cmd.append(self.crate)

        ver_label = f"@{target_ver}" if target_ver else ""
        print(f"[{pkg.name}] Building and installing {self.crate}{ver_label} via cargo install...")
        env = os.environ.copy()
        env["PATH"] = f"{BIN_DIR}:{Path.home() / '.cargo' / 'bin'}:{env.get('PATH', '')}"
        subprocess.run(cmd, env=env, check=True)

        for b in self.bins:
            link_name, _ = parse_bin_spec(b)
            cargo_target = Path.home() / ".cargo" / "bin" / link_name
            if cargo_target.exists():
                link_executable(cargo_target, link_name)

        return target_ver or "installed"

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

    def lock(self, _pkg: "Pkg") -> Dict[str, Any]:
        data = fetch_json(f"https://pypi.org/pypi/{self.package}/json")
        return {"version": data["info"]["version"]}

    def install(
        self,
        pkg: "Pkg",
        force: bool,
        state: Dict[str, str],
        lock_entry: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
        uv_bin = self._find_uv()
        target_ver = lock_entry["version"] if lock_entry else None
        installed_ver = state.get(pkg.name)
        if not force and installed_ver and (target_ver is None or installed_ver == target_ver) and self.is_installed(pkg):
            print(f"[{pkg.name}] Already up to date ({installed_ver})")
            return None

        pkg_spec = f"{self.package}=={target_ver}" if target_ver else self.package
        cmd = [str(uv_bin), "tool", "install"]
        if force:
            cmd.append("--force")
        if self.python:
            cmd.extend(["-p", self.python])
        cmd.append(pkg_spec)

        print(f"[{pkg.name}] Installing {pkg_spec} via uv tool install...")
        BIN_DIR.mkdir(parents=True, exist_ok=True)
        BIN_DIR.chmod(0o755)
        env = os.environ.copy()
        env["UV_TOOL_BIN_DIR"] = str(BIN_DIR)
        env["PATH"] = f"{BIN_DIR}:{env.get('PATH', '')}"
        subprocess.run(cmd, env=env, check=True)

        return target_ver or "installed"

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
        install: Callable[["Pkg", bool, Dict[str, str], Optional[Dict[str, Any]]], Optional[str]],
        remove: Callable[["Pkg"], None],
        is_installed: Callable[["Pkg"], bool],
        lock: Callable[["Pkg"], Dict[str, Any]],
        depends: Sequence[str] = (),
    ):
        self._install = install
        self._remove = remove
        self._is_installed = is_installed
        self._lock = lock
        self.depends = list(depends)

    def lock(self, pkg: "Pkg") -> Dict[str, Any]:
        return self._lock(pkg)

    def install(
        self,
        pkg: "Pkg",
        force: bool,
        state: Dict[str, str],
        lock_entry: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
        return self._install(pkg, force, state, lock_entry)

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

    def is_installed(self, name: str) -> bool:
        if name not in self.packages:
            raise ValueError(f"Unknown package: {name}")
        pkg = self.packages[name]
        return pkg.source.is_installed(pkg)

    def lock(self, names: Optional[Sequence[str]] = None) -> None:
        targets = list(names) if names else list(self.packages.keys())
        lock_data = load_lock()
        for name in targets:
            if name not in self.packages:
                raise ValueError(f"Unknown package: {name}")
            pkg = self.packages[name]
            print(f"[{name}] Locking latest version and checksum...")
            entry = pkg.source.lock(pkg)
            lock_data[name] = entry
            save_lock(lock_data)
            ver = entry.get("version", "-")
            sha = entry.get("sha256") or entry.get("commit", "")
            sha_short = f" ({sha[:12]})" if sha else ""
            print(f"[{name}] Locked -> {ver}{sha_short}")

    def install(self, name: str, force: bool = False, allow_unlocked: bool = False) -> None:
        if name not in self.packages:
            raise ValueError(f"Unknown package: {name}")
        pkg = self.packages[name]

        for dep in pkg.all_depends:
            self.install(dep, force=False, allow_unlocked=allow_unlocked)

        lock_data = load_lock()
        lock_entry = lock_data.get(name)
        if lock_entry is None and not allow_unlocked:
            raise RuntimeError(
                f"Package '{name}' is not present in {LOCK_FILE.name}. "
                f"Run 'pkg.py lock {name}' on a trusted machine first, or pass --allow-unlocked."
            )

        state = load_state()
        new_version = pkg.source.install(pkg, force=force, state=state, lock_entry=lock_entry)
        if new_version is not None:
            state = load_state()
            state[name] = new_version
            save_state(state)
            print(f"[{name}] Done ({new_version})")

    def update(self, name: str, force: bool = False, allow_unlocked: bool = False) -> None:
        if name not in self.packages:
            raise ValueError(f"Unknown package: {name}")
        if not self.is_installed(name):
            print(f"[{name}] Not installed, skipping")
            return
        self.install(name, force=force, allow_unlocked=allow_unlocked)

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
        lock_data = load_lock()
        print(
            f"{'PACKAGE':<22} {'DEFAULT':<8} {'LOCKED':<14} {'INSTALLED':<14} {'DESCRIPTION'}"
        )
        print("-" * 88)
        for name, pkg in self.packages.items():
            is_def = "yes" if pkg.default else "no"
            lock_ver = lock_data.get(name, {}).get("version", "-")
            ver = state.get(name, "-")
            bins_ok = pkg.source.is_installed(pkg)
            if ver != "-" and not bins_ok:
                ver = f"{ver} (broken)"
            elif ver == "-" and bins_ok:
                ver = "installed"
            print(f"{name:<22} {is_def:<8} {lock_ver:<14} {ver:<14} {pkg.desc}")


def run_cli(packages: Sequence[Pkg]) -> None:
    pm = PackageManager(packages)
    parser = argparse.ArgumentParser(
        description="Lightweight user-space package manager (~/.local)"
    )
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("list", aliases=["status", "ls"], help="List packages and installation status")

    p_lock = sub.add_parser("lock", help="Resolve latest versions/checksums into pkg-lock.json")
    p_lock.add_argument(
        "packages", nargs="*", help="Package names to lock (default: all packages)"
    )

    p_install = sub.add_parser("install", aliases=["i"], help="Install locked packages")
    p_install.add_argument(
        "packages", nargs="*", help="Package names (default: all default packages)"
    )
    p_install.add_argument(
        "-a", "--all", action="store_true", help="Install all packages including optional ones"
    )
    p_install.add_argument(
        "-f", "--force", action="store_true", help="Force reinstall even if up to date"
    )
    p_install.add_argument(
        "--allow-unlocked",
        action="store_true",
        help="Allow dynamic version resolution if package is missing from pkg-lock.json",
    )

    p_update = sub.add_parser(
        "update", aliases=["up"], help="Sync installed packages to locked versions"
    )
    p_update.add_argument(
        "packages", nargs="*", help="Package names (default: all installed packages)"
    )
    p_update.add_argument(
        "-a", "--all", action="store_true", help="Update all installed packages"
    )
    p_update.add_argument(
        "-f", "--force", action="store_true", help="Force reinstall even if up to date"
    )
    p_update.add_argument(
        "--allow-unlocked",
        action="store_true",
        help="Allow dynamic version resolution if package is missing from pkg-lock.json",
    )

    p_remove = sub.add_parser("remove", aliases=["rm", "uninstall"], help="Remove packages")
    p_remove.add_argument("packages", nargs="+", help="Package names to remove")

    args = parser.parse_args()

    if not args.cmd or args.cmd in ("list", "status", "ls"):
        pm.list_packages()
        return

    if args.cmd == "lock":
        targets = args.packages if args.packages else list(pm.packages.keys())
        failed = []
        for name in targets:
            try:
                pm.lock([name])
            except Exception as e:
                print(f"[{name}] ERROR locking: {e}", file=sys.stderr)
                failed.append(name)
        if failed:
            sys.exit(1)

    elif args.cmd in ("install", "i"):
        if args.all:
            targets = list(pm.packages.keys())
        elif args.packages:
            targets = args.packages
        else:
            targets = [name for name, p in pm.packages.items() if p.default]

        failed = []
        for name in targets:
            try:
                pm.install(name, force=args.force, allow_unlocked=args.allow_unlocked)
            except Exception as e:
                print(f"[{name}] ERROR: {e}", file=sys.stderr)
                failed.append(name)
        if failed:
            sys.exit(1)

    elif args.cmd in ("update", "up"):
        if args.packages:
            targets = args.packages
        else:
            targets = [name for name in pm.packages if pm.is_installed(name)]

        failed = []
        for name in targets:
            try:
                pm.update(name, force=args.force, allow_unlocked=args.allow_unlocked)
            except Exception as e:
                print(f"[{name}] ERROR: {e}", file=sys.stderr)
                failed.append(name)
        if failed:
            sys.exit(1)

    elif args.cmd in ("remove", "rm", "uninstall"):
        for name in args.packages:
            pm.remove(name)
