"""Configuration, paths, and custom overlay manifest loading for Groundhog."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

STOW_PACKAGES: tuple[str, ...] = (
    "zsh",
    "git",
    "tmux",
    "nvim",
    "ghostty",
    "gh",
    "atuin",
    "bat",
    "btop",
    "lazygit",
    "vscode",
    "nushell",
)

# Never fold these directories into single directory symlinks because apps write
# untracked runtime state, caches, or tokens alongside configuration files.
NO_FOLDING_PACKAGES: frozenset[str] = frozenset({"git", "gh", "vscode", "nushell"})

TPM_REPO = "https://github.com/tmux-plugins/tpm"
TPM_COMMIT = "99469c4a9b1ccf77fade25842dc7bafbc8ce9946"

# Pinned Homebrew/install commit SHA (avoids blind curl-pipe-bash from HEAD).
HOMEBREW_INSTALL_COMMIT = "870ddff5dbe61d293a8b4a763090d125e59048a1"
HOMEBREW_INSTALL_URL = (
    f"https://raw.githubusercontent.com/Homebrew/install/{HOMEBREW_INSTALL_COMMIT}/install.sh"
)

ANSIBLE_SUDOERS_TMP = Path("/etc/sudoers.d/99-groundhog-ansible")


@dataclass(frozen=True)
class GroundhogPaths:
    """Resolved filesystem paths for a Groundhog run (injectable for tests)."""

    repo_dir: Path
    home_dir: Path

    @classmethod
    def default(cls) -> GroundhogPaths:
        repo_env = os.environ.get("GROUNDHOG_DIR")
        if repo_env:
            repo_dir = Path(repo_env).expanduser().resolve()
        else:
            # src/groundhog/config.py -> repo root is two parents up from src/
            repo_dir = Path(__file__).resolve().parents[2]
        return cls(repo_dir=repo_dir, home_dir=Path.home())

    @property
    def custom_dir(self) -> Path:
        return self.repo_dir / "custom"

    @property
    def custom_example_dir(self) -> Path:
        return self.repo_dir / "custom.example"

    @property
    def backup_dir(self) -> Path:
        return self.home_dir / ".backups"

    @property
    def ansible_playbook(self) -> Path:
        return self.repo_dir / "ansible" / "setup.yml"

    @property
    def homebrew_brewfile(self) -> Path:
        return self.repo_dir / "homebrew" / ".Brewfile"

    @property
    def custom_brewfile(self) -> Path:
        return self.custom_dir / "Brewfile"

    @property
    def local_brewfile(self) -> Path:
        return self.repo_dir / "homebrew" / ".Brewfile.local"

    @property
    def launcher_script(self) -> Path:
        return self.repo_dir / "groundhog"

    @property
    def local_bin_dir(self) -> Path:
        return self.home_dir / ".local" / "bin"


def expand_home(raw: str, home_dir: Path) -> Path:
    """Expand leading `~` and `$HOME` references against `home_dir`."""
    home_str = str(home_dir)
    expanded = raw
    if expanded == "~":
        expanded = home_str
    elif expanded.startswith("~/"):
        expanded = home_str + expanded[1:]
    expanded = expanded.replace("$HOME", home_str)
    return Path(expanded)


def parse_manifest_lines(
    text: str,
    custom_dir: Path,
    home_dir: Path,
) -> list[tuple[Path, Path]]:
    """Parse `src:target` lines from custom/links.conf or custom/copies.conf."""
    entries: list[tuple[Path, Path]] = []
    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise ValueError(f"Line {lineno}: expected 'src:target', got {line!r}")
        src_rel, target_raw = line.split(":", 1)
        src_rel = src_rel.strip()
        target_raw = target_raw.strip()
        if not src_rel or not target_raw:
            raise ValueError(f"Line {lineno}: empty source or target in {line!r}")
        entries.append((custom_dir / src_rel, expand_home(target_raw, home_dir)))
    return entries


def load_custom_manifest(
    manifest_path: Path,
    custom_dir: Path,
    home_dir: Path,
) -> list[tuple[Path, Path]]:
    """Load entries from a custom manifest file if it exists."""
    if not manifest_path.is_file():
        return []
    return parse_manifest_lines(manifest_path.read_text(encoding="utf-8"), custom_dir, home_dir)


def manual_links(paths: GroundhogPaths) -> list[tuple[Path, Path]]:
    """Return core + custom file-level symlinks."""
    links: list[tuple[Path, Path]] = [
        (paths.repo_dir / "ssh" / ".ssh" / "config", paths.home_dir / ".ssh" / "config"),
        (paths.launcher_script, paths.local_bin_dir / "groundhog"),
    ]
    links.extend(
        load_custom_manifest(paths.custom_dir / "links.conf", paths.custom_dir, paths.home_dir)
    )
    return links


def app_copies(paths: GroundhogPaths) -> list[tuple[Path, Path]]:
    """Return app-managed file copies from custom/copies.conf."""
    return load_custom_manifest(
        paths.custom_dir / "copies.conf",
        paths.custom_dir,
        paths.home_dir,
    )
