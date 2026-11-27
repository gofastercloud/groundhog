"""Safe existing-Mac adoption (`groundhog adopt`) and rollback (`groundhog clean`).

Stdlib-only. Never copies secrets into `custom/`, always snapshots conflicting
files with a `manifest.json` before modifying anything, and emits `--json` so
an AI agent can drive semantic merges and incremental Ansible rollout.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import urllib.parse
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path

from groundhog.config import STOW_PACKAGES, GroundhogPaths, manual_links
from groundhog.ops import cmd_init_custom, cmd_unlink, get_targets, is_managed_link

SECRET_LINE_RE = re.compile(
    r"(?:^|\s)(?:export\s+)?[A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH)[A-Z0-9_]*\s*="
    r"|gh[pousr]_[A-Za-z0-9]{20,}"
    r"|sk-[A-Za-z0-9]{20,}"
    r"|AKIA[0-9A-Z]{16}",
)

BREW_ENTRY_RE = re.compile(r'^(tap|brew|cask|mas|vscode)\s+"([^"]+)"')

MANAGED_BIN_NAMES: tuple[str, ...] = (
    "groundhog",
    "agent-git",
    "agent-gh",
    "agent-box",
    "agency-install",
    "agency-dash",
    "agency-report",
    "interactive-shell",
    "ghostty-tmux",
)


@dataclass
class AdoptPlan:
    """Read-only discovery report of an existing Mac before adopting Groundhog."""

    conflicts: list[str] = field(default_factory=list)
    extra_brew_lines: list[str] = field(default_factory=list)
    dock_apps: list[str] = field(default_factory=list)
    git_identity: dict[str, str] = field(default_factory=dict)
    ssh_config_present: bool = False
    zshrc_present: bool = False
    secret_warnings: list[str] = field(default_factory=list)
    custom_exists: bool = False

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def _brew_keys(text: str) -> set[tuple[str, str]]:
    keys: set[tuple[str, str]] = set()
    for line in text.splitlines():
        m = BREW_ENTRY_RE.match(line.strip())
        if m:
            keys.add((m.group(1), m.group(2).lower()))
    return keys


def _discover_extra_brew(paths: GroundhogPaths) -> list[str]:
    if not shutil.which("brew"):
        return []
    proc = subprocess.run(
        ["brew", "bundle", "dump", "--file=-"],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        return []
    known: set[tuple[str, str]] = set()
    for bf in (paths.homebrew_brewfile, paths.custom_brewfile, paths.local_brewfile):
        if bf.is_file():
            known |= _brew_keys(bf.read_text(encoding="utf-8", errors="replace"))
    extras: list[str] = []
    for raw in proc.stdout.splitlines():
        line = raw.strip()
        m = BREW_ENTRY_RE.match(line)
        if m and (m.group(1), m.group(2).lower()) not in known:
            extras.append(line)
    return extras


def _discover_dock_apps() -> list[str]:
    if sys.platform != "darwin" or not shutil.which("defaults"):
        return []
    proc = subprocess.run(
        ["defaults", "export", "com.apple.dock", "-"],
        capture_output=True,
        timeout=10,
        check=False,
    )
    if proc.returncode != 0 or not proc.stdout:
        return []
    try:
        plist = plistlib.loads(proc.stdout)
    except Exception:
        return []
    apps: list[str] = []
    for item in plist.get("persistent-apps", []):
        if not isinstance(item, dict):
            continue
        url = item.get("tile-data", {}).get("file-data", {}).get("_CFURLString")
        if not isinstance(url, str):
            continue
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme == "file":
            app_path = urllib.parse.unquote(parsed.path).rstrip("/")
            if app_path.endswith(".app"):
                apps.append(app_path)
    return apps


def _discover_git_identity(paths: GroundhogPaths) -> dict[str, str]:
    gitconfig = paths.home_dir / ".gitconfig"
    if not gitconfig.is_file() or is_managed_link(paths, gitconfig):
        return {}
    out: dict[str, str] = {}
    for key in ("user.name", "user.email", "user.signingkey"):
        proc = subprocess.run(
            ["git", "config", "--file", str(gitconfig), "--get", key],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            out[key] = proc.stdout.strip()
    return out


def _scan_shell_secrets(paths: GroundhogPaths) -> list[str]:
    warnings: list[str] = []
    for rel in (".zshrc", ".zprofile"):
        p = paths.home_dir / rel
        if not p.is_file() or is_managed_link(paths, p):
            continue
        for lineno, line in enumerate(
            p.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if SECRET_LINE_RE.search(stripped):
                warnings.append(f"~/{rel}:{lineno} looks like a secret/token assignment")
    return warnings


def scan_adopt(paths: GroundhogPaths, *, include_system: bool = True) -> AdoptPlan:
    """Inspect `$HOME` (and optionally Homebrew/Dock) without modifying anything."""
    plan = AdoptPlan(custom_exists=paths.custom_dir.is_dir())
    seen: set[str] = set()

    def _check_conflict(target: Path) -> None:
        if not (target.exists() or target.is_symlink()):
            return
        if is_managed_link(paths, target):
            return
        try:
            rel = str(target.relative_to(paths.home_dir))
        except ValueError:
            rel = str(target)
        if rel not in seen:
            seen.add(rel)
            plan.conflicts.append(rel)

    for pkg in STOW_PACKAGES:
        for rel in get_targets(paths, pkg):
            _check_conflict(paths.home_dir / rel)
    for _, dst in manual_links(paths):
        _check_conflict(dst)

    plan.conflicts.sort()
    plan.git_identity = _discover_git_identity(paths)
    ssh_cfg = paths.home_dir / ".ssh" / "config"
    plan.ssh_config_present = ssh_cfg.is_file() and not is_managed_link(paths, ssh_cfg)
    zshrc = paths.home_dir / ".zshrc"
    plan.zshrc_present = zshrc.is_file() and not is_managed_link(paths, zshrc)
    plan.secret_warnings = _scan_shell_secrets(paths)

    if include_system:
        plan.extra_brew_lines = _discover_extra_brew(paths)
        plan.dock_apps = _discover_dock_apps()
    return plan


def _backup_conflicts(paths: GroundhogPaths, plan: AdoptPlan) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest_root = paths.backup_dir / f"groundhog-adopt-{stamp}"
    dest_root.mkdir(parents=True, exist_ok=True)
    os.chmod(dest_root, 0o700)

    manifest_files: list[dict[str, object]] = []
    for rel in plan.conflicts:
        src = paths.home_dir / rel
        if not (src.exists() or src.is_symlink()):
            continue
        dst = dest_root / "files" / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src.is_symlink():
            os.symlink(os.readlink(src), dst)
            manifest_files.append({"rel": rel, "kind": "symlink"})
        elif src.is_dir():
            shutil.copytree(src, dst, symlinks=True)
            manifest_files.append({"rel": rel, "kind": "dir"})
        else:
            shutil.copy2(src, dst)
            manifest_files.append({"rel": rel, "kind": "file"})

    manifest = {
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "home_dir": str(paths.home_dir),
        "files": manifest_files,
        "dock_apps": plan.dock_apps,
    }
    (dest_root / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return dest_root


def _apply_adopt_files(paths: GroundhogPaths, plan: AdoptPlan, *, quiet: bool = False) -> list[str]:
    written: list[str] = []
    if not paths.custom_dir.is_dir():
        if quiet:
            with contextlib.redirect_stdout(io.StringIO()):
                cmd_init_custom(paths)
        else:
            cmd_init_custom(paths)
        written.append("custom/ (initialised)")

    if plan.extra_brew_lines:
        bf = paths.custom_brewfile
        existing = bf.read_text(encoding="utf-8") if bf.is_file() else ""
        stamp = datetime.now().strftime("%Y-%m-%d")
        block = (
            f"\n# Adopted from existing Mac on {stamp}\n" + "\n".join(plan.extra_brew_lines) + "\n"
        )
        bf.write_text(existing.rstrip() + "\n" + block, encoding="utf-8")
        written.append(f"custom/Brewfile (+{len(plan.extra_brew_lines)} packages)")

    if plan.dock_apps:
        cfg = paths.custom_dir / "config.yml"
        existing = cfg.read_text(encoding="utf-8") if cfg.is_file() else "---\n"
        if not re.search(r"^dock_apps:", existing, re.M):
            dock_yaml = "\ndock_apps:\n" + "".join(f"  - {app}\n" for app in plan.dock_apps)
            cfg.write_text(existing.rstrip() + "\n" + dock_yaml, encoding="utf-8")
            written.append(f"custom/config.yml (dock_apps: {len(plan.dock_apps)})")

    if plan.git_identity.get("user.name") or plan.git_identity.get("user.email"):
        gc = paths.custom_dir / "gitconfig"
        existing = gc.read_text(encoding="utf-8") if gc.is_file() else ""
        if "name =" not in existing:
            lines = ["[user]"]
            if "user.name" in plan.git_identity:
                lines.append(f"    name = {plan.git_identity['user.name']}")
            if "user.email" in plan.git_identity:
                lines.append(f"    email = {plan.git_identity['user.email']}")
            gc.write_text("\n".join(lines) + "\n", encoding="utf-8")
            written.append("custom/gitconfig")

    if "user.signingkey" in plan.git_identity:
        gl = paths.home_dir / ".gitconfig.local"
        if not gl.exists():
            gl.write_text(
                f"[user]\n    signingkey = {plan.git_identity['user.signingkey']}\n",
                encoding="utf-8",
            )
            written.append("~/.gitconfig.local (signingkey)")

    if plan.ssh_config_present:
        ssh_local = paths.home_dir / ".ssh" / "config.local"
        if not ssh_local.exists():
            shutil.copy2(paths.home_dir / ".ssh" / "config", ssh_local)
            os.chmod(ssh_local, 0o600)
            written.append("~/.ssh/config.local")

    if plan.zshrc_present and not plan.secret_warnings:
        zlocal = paths.home_dir / ".zshrc.local"
        if not zlocal.exists():
            shutil.copy2(paths.home_dir / ".zshrc", zlocal)
            written.append("~/.zshrc.local")

    return written


def cmd_adopt(
    paths: GroundhogPaths,
    *,
    apply: bool = False,
    as_json: bool = False,
    include_system: bool = True,
) -> int:
    """Audit an existing Mac and optionally snapshot + adopt configs into custom/ and *.local."""
    plan = scan_adopt(paths, include_system=include_system)
    if as_json and not apply:
        print(json.dumps(plan.to_dict(), indent=2))
        return 0

    if not apply:
        print("Groundhog Adopt — Dry-Run Audit (no files modified)\n")
        print(f"  Conflicting dotfiles to back up: {len(plan.conflicts)}")
        for rel in plan.conflicts:
            print(f"    - ~/{rel}")
        print(f"  Extra Homebrew/VS Code entries → custom/Brewfile: {len(plan.extra_brew_lines)}")
        print(f"  Current Dock apps → custom/config.yml:            {len(plan.dock_apps)}")
        if plan.git_identity:
            keys = ", ".join(plan.git_identity)
            print(f"  Git identity found:                               {keys}")
        if plan.ssh_config_present:
            print("  Existing ~/.ssh/config → ~/.ssh/config.local")
        if plan.zshrc_present:
            dest = (
                "(SKIPPED: secret warnings — review manually)"
                if plan.secret_warnings
                else "→ ~/.zshrc.local"
            )
            print(f"  Existing ~/.zshrc      {dest}")
        if plan.secret_warnings:
            print(
                "\n  WARNING — Potential secrets detected"
                " (will NOT be copied to custom/ or *.local):"
            )
            for w in plan.secret_warnings:
                print(f"    ! {w}")
        print(
            "\nRecommended: let your AI coding agent drive adoption"
            " using skills/groundhog/SKILL.md."
        )
        print("To snapshot backups and populate custom/ + *.local now, run:")
        print("  ./groundhog adopt --apply")
        return 0

    backup_dir = _backup_conflicts(paths, plan)
    written = _apply_adopt_files(paths, plan, quiet=as_json)
    if as_json:
        print(
            json.dumps(
                {"backup_dir": str(backup_dir), "written": written, "plan": plan.to_dict()},
                indent=2,
            )
        )
        return 0

    print(f"Snapshot saved to: {backup_dir}")
    for item in written:
        print(f"  adopted: {item}")
    if plan.secret_warnings:
        print(
            "\n  NOTE: ~/.zshrc was backed up but NOT copied to ~/.zshrc.local"
            " due to secret warnings:"
        )
        for w in plan.secret_warnings:
            print(f"    ! {w}")
    print("\nNext steps (no Ansible changes have been applied yet):")
    print("  1. Review custom/ (or ask your AI agent to trim Brewfile and merge configs).")
    print('  2. Dry-run incrementally: ./groundhog check --tags "dotfiles,dev-tools"')
    print('  3. Apply when ready:      ./groundhog ansible --tags "dotfiles,dev-tools"')
    print(f"  4. Roll back any time:    ./groundhog clean --restore {backup_dir}")
    return 0


def _latest_adopt_backup(paths: GroundhogPaths) -> Path | None:
    if not paths.backup_dir.is_dir():
        return None
    candidates = sorted(
        (
            p
            for p in paths.backup_dir.iterdir()
            if p.is_dir() and p.name.startswith("groundhog-adopt-")
        ),
        key=lambda p: p.name,
    )
    return candidates[-1] if candidates else None


def _is_groundhog_wrapper(paths: GroundhogPaths, bin_path: Path) -> bool:
    if bin_path.is_symlink():
        return is_managed_link(paths, bin_path)
    if bin_path.is_file():
        head = bin_path.read_text(encoding="utf-8", errors="replace")[:300]
        return "Managed by Groundhog" in head or str(paths.repo_dir) in head
    return False


def cmd_clean(
    paths: GroundhogPaths,
    *,
    restore: str | None = None,
    restore_latest: bool = False,
    dry_run: bool = False,
) -> int:
    """Remove Groundhog symlinks/wrappers and optionally restore a pre-adoption backup."""
    backup_dir: Path | None = None
    if restore:
        backup_dir = Path(restore).expanduser().resolve()
    elif restore_latest:
        backup_dir = _latest_adopt_backup(paths)
        if backup_dir is None:
            print("No groundhog-adopt-* backup found under ~/.backups/.", file=sys.stderr)
            return 1

    if backup_dir is not None and not (backup_dir / "manifest.json").is_file():
        print(f"Backup manifest not found at {backup_dir / 'manifest.json'}.", file=sys.stderr)
        return 1

    manual_to_remove = [dst for _, dst in manual_links(paths) if is_managed_link(paths, dst)]
    bins_to_remove = [
        paths.local_bin_dir / name
        for name in MANAGED_BIN_NAMES
        if _is_groundhog_wrapper(paths, paths.local_bin_dir / name)
    ]

    if dry_run:
        print("Groundhog Clean — Dry Run (no files modified)")
        print("  Would unstow all Groundhog Stow packages")
        for p in manual_to_remove:
            print(f"  Would remove symlink: {p}")
        for p in bins_to_remove:
            print(f"  Would remove wrapper: {p}")
        if backup_dir is not None:
            manifest = json.loads((backup_dir / "manifest.json").read_text(encoding="utf-8"))
            for entry in manifest.get("files", []):
                print(f"  Would restore: ~/{entry['rel']} (from {backup_dir.name})")
        return 0

    cmd_unlink(paths)
    for p in manual_to_remove:
        p.unlink(missing_ok=True)
        print(f"  removed link: {p}")
    for p in bins_to_remove:
        p.unlink(missing_ok=True)
        print(f"  removed bin:  {p}")

    if backup_dir is not None:
        manifest = json.loads((backup_dir / "manifest.json").read_text(encoding="utf-8"))
        for entry in manifest.get("files", []):
            rel = str(entry["rel"])
            kind = str(entry.get("kind", "file"))
            src = backup_dir / "files" / rel
            dst = paths.home_dir / rel
            if not (src.exists() or src.is_symlink()):
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.is_symlink() or dst.is_file():
                dst.unlink()
            elif dst.is_dir():
                shutil.rmtree(dst)
            if kind == "symlink" or src.is_symlink():
                os.symlink(os.readlink(src), dst)
            elif kind == "dir" or src.is_dir():
                shutil.copytree(src, dst, symlinks=True)
            else:
                shutil.copy2(src, dst)
            print(f"  restored: ~/{rel}")

    print(
        "\nGroundhog links and wrappers cleaned."
        " Homebrew packages, ~/.ssh keys, and custom/ were left untouched."
    )
    return 0
