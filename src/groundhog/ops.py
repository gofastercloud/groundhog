"""Core Groundhog workstation operations (stow, overlay, hooks, brew, ansible)."""

from __future__ import annotations

import difflib
import filecmp
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import TextIO

from groundhog.config import (
    ANSIBLE_SUDOERS_TMP,
    HOMEBREW_INSTALL_URL,
    NO_FOLDING_PACKAGES,
    STOW_PACKAGES,
    TPM_COMMIT,
    TPM_REPO,
    GroundhogPaths,
    app_copies,
    load_custom_manifest,
    manual_links,
)


class Style:
    """Minimal ANSI styler that degrades cleanly when stdout is not a TTY."""

    def __init__(self, stream: TextIO | None = None) -> None:
        self.stream = stream or sys.stdout
        enabled = (
            hasattr(self.stream, "isatty")
            and self.stream.isatty()
            and not os.environ.get("NO_COLOR")
        )
        self.red = "\033[0;31m" if enabled else ""
        self.green = "\033[0;32m" if enabled else ""
        self.yellow = "\033[1;33m" if enabled else ""
        self.blue = "\033[0;34m" if enabled else ""
        self.dim = "\033[2m" if enabled else ""
        self.nc = "\033[0m" if enabled else ""


@dataclass
class StatusSummary:
    """Structured snapshot used by both the CLI and interactive TUI."""

    stowed_ok: int = 0
    stowed_total: int = 0
    links_ok: int = 0
    links_total: int = 0
    copies_ok: int = 0
    copies_total: int = 0
    custom_present: bool = False
    brew_formulae: int | None = None
    brew_casks: int | None = None
    warnings: list[str] = field(default_factory=list)


STATIC_TARGETS: dict[str, tuple[str, ...]] = {
    "zsh": (".zshrc", ".zprofile"),
    "git": (".gitconfig", ".config/git/template/hooks/pre-commit"),
    "tmux": (".tmux.conf", ".tmux.mobile.conf"),
    "nvim": (".config/nvim",),
    "ghostty": (".config/ghostty",),
    "gh": (".config/gh/config.yml",),
    "atuin": (".config/atuin/config.toml",),
    "bat": (".config/bat/config",),
    "btop": (".config/btop/btop.conf",),
    "lazygit": (".config/lazygit",),
    "vscode": (
        "Library/Application Support/Code/User/settings.json",
        "Library/Application Support/Code/User/keybindings.json",
    ),
}


def get_targets(paths: GroundhogPaths, pkg: str) -> list[str]:
    """Return relative target paths for a Stow package."""
    if pkg in STATIC_TARGETS:
        return list(STATIC_TARGETS[pkg])
    if pkg == "nushell":
        pkg_dir = paths.repo_dir / "nushell"
        if not pkg_dir.is_dir():
            return []
        return sorted(str(p.relative_to(pkg_dir)) for p in pkg_dir.rglob("*") if p.is_file())
    return []


def is_managed_link(paths: GroundhogPaths, link_path: Path) -> bool:
    """Return True if `link_path` is a symlink pointing inside `paths.repo_dir`."""
    if not link_path.is_symlink():
        return False
    raw_target = os.readlink(link_path)
    repo_str = str(paths.repo_dir)
    repo_resolved = str(paths.repo_dir.resolve())
    if raw_target.startswith(repo_str) or raw_target.startswith(repo_resolved):
        return True
    try:
        resolved = (link_path.parent / raw_target).resolve()
        return str(resolved).startswith(repo_resolved)
    except OSError:
        return False


def ensure_git_checkout(repo_url: str, target_dir: Path, commit: str) -> None:
    """Clone `repo_url` (blobless) if absent and detach HEAD at pinned `commit`."""
    if not (target_dir / ".git").is_dir():
        target_dir.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "clone", "--filter=blob:none", "--no-checkout", repo_url, str(target_dir)],
            check=True,
        )
    has_commit = subprocess.run(
        ["git", "-C", str(target_dir), "cat-file", "-e", f"{commit}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if has_commit.returncode != 0:
        subprocess.run(
            ["git", "-C", str(target_dir), "fetch", "--depth", "1", "origin", commit],
            check=True,
        )
    subprocess.run(
        ["git", "-C", str(target_dir), "checkout", "--quiet", "--detach", commit],
        check=True,
    )


def _app_copy_check(
    src: Path,
    target: Path,
    *,
    seed: bool,
    style: Style,
    out: TextIO,
) -> bool:
    """Check (or seed) an app-managed copy. Returns True when in sync."""
    if target.is_symlink():
        if seed:
            target.unlink()
            shutil.copy2(src, target)
            print(f"  {style.green}→{style.nc} {target} (symlink replaced with a copy)", file=out)
            return True
        print(
            f"  {style.yellow}⚠{style.nc} {target} (still a symlink; run groundhog link)",
            file=out,
        )
        return False
    if not target.exists():
        if seed:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
            print(f"  {style.green}→{style.nc} {target} (seeded from repo)", file=out)
            return True
        print(f"  {style.yellow}○{style.nc} {target} (missing)", file=out)
        return False
    if filecmp.cmp(src, target, shallow=False):
        print(f"  {style.green}✓{style.nc} {target} (matches repo)", file=out)
        return True
    print(
        f"  {style.yellow}≠{style.nc} {target} (changed by the app; run groundhog capture)",
        file=out,
    )
    return False


def _install_repo_hooks(repo_dir: Path, label: str, *, style: Style, out: TextIO) -> bool:
    """Install pre-commit and pre-push hooks for a Git repo if configured."""
    if not (repo_dir / ".git").exists() or not (repo_dir / ".pre-commit-config.yaml").is_file():
        return True
    if not shutil.which("pre-commit") or not shutil.which("gitleaks"):
        print(
            f"  {style.yellow}⚠{style.nc} Skipping {label} hooks "
            "(install pre-commit and gitleaks for local secret & lint guards)",
            file=out,
        )
        return False
    subprocess.run(
        [
            "pre-commit",
            "install",
            "--hook-type",
            "pre-commit",
            "--hook-type",
            "pre-push",
            "--install-hooks",
        ],
        cwd=repo_dir,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    print(f"  {style.green}✓{style.nc} {label}: pre-commit & pre-push hooks installed", file=out)
    return True


def collect_status(paths: GroundhogPaths, *, include_brew: bool = True) -> StatusSummary:
    """Collect structured Groundhog status without printing."""
    summary = StatusSummary(custom_present=paths.custom_dir.is_dir())
    for pkg in STOW_PACKAGES:
        for rel in get_targets(paths, pkg):
            summary.stowed_total += 1
            home_file = paths.home_dir / rel
            if home_file.is_symlink() and is_managed_link(paths, home_file):
                summary.stowed_ok += 1
            else:
                summary.warnings.append(f"{pkg}: {rel}")

    for src, target in manual_links(paths):
        if not src.exists():
            continue
        summary.links_total += 1
        if target.is_symlink() and Path(os.readlink(target)) == src:
            summary.links_ok += 1
        else:
            summary.warnings.append(f"link: {target}")

    for src, target in app_copies(paths):
        if not src.exists():
            continue
        summary.copies_total += 1
        if target.is_file() and not target.is_symlink() and filecmp.cmp(src, target, shallow=False):
            summary.copies_ok += 1
        else:
            summary.warnings.append(f"copy: {target}")

    if include_brew and shutil.which("brew"):
        try:
            formulae = subprocess.check_output(["brew", "list", "--formula"], text=True)
            casks = subprocess.check_output(["brew", "list", "--cask"], text=True)
            summary.brew_formulae = len([line for line in formulae.splitlines() if line.strip()])
            summary.brew_casks = len([line for line in casks.splitlines() if line.strip()])
        except subprocess.SubprocessError:
            pass
    return summary


def cmd_status(paths: GroundhogPaths, *, out: TextIO | None = None) -> int:
    """Print detailed link, overlay, and Homebrew status."""
    out = out or sys.stdout
    s = Style(out)
    print(f"{s.blue}Groundhog status:{s.nc}\n", file=out)

    for pkg in STOW_PACKAGES:
        print(f"{s.yellow}[{pkg}]{s.nc}", file=out)
        for rel in get_targets(paths, pkg):
            home_file = paths.home_dir / rel
            if home_file.is_symlink():
                if is_managed_link(paths, home_file):
                    print(f"  {s.green}✓{s.nc} {rel}", file=out)
                else:
                    print(f"  {s.red}⚠{s.nc} {rel} -> {os.readlink(home_file)}", file=out)
            elif home_file.exists():
                print(f"  {s.red}✗{s.nc} {rel} (not linked)", file=out)
            else:
                print(f"  {s.yellow}○{s.nc} {rel} (missing)", file=out)

    print(f"\n{s.yellow}[manual & custom symlinks]{s.nc}", file=out)
    for src, target in manual_links(paths):
        if target.is_symlink():
            if Path(os.readlink(target)) == src:
                print(f"  {s.green}✓{s.nc} {target}", file=out)
            else:
                print(f"  {s.red}⚠{s.nc} {target} -> {os.readlink(target)}", file=out)
        elif target.exists():
            print(f"  {s.red}✗{s.nc} {target} (not linked)", file=out)
        else:
            print(f"  {s.yellow}○{s.nc} {target} (missing)", file=out)

    copies = app_copies(paths)
    if copies:
        print(f"\n{s.yellow}[app-managed copies]{s.nc}", file=out)
        for src, target in copies:
            _app_copy_check(src, target, seed=False, style=s, out=out)

    print(f"\n{s.yellow}[custom overlay]{s.nc}", file=out)
    if paths.custom_dir.is_dir():
        print(f"  {s.green}✓{s.nc} {paths.custom_dir}", file=out)
    else:
        print(
            f"  {s.yellow}○{s.nc} none (run ./groundhog init-custom to create one)",
            file=out,
        )

    print(f"\n{s.yellow}[homebrew]{s.nc}", file=out)
    if shutil.which("brew"):
        summary = collect_status(paths, include_brew=True)
        print(f"  {s.green}✓{s.nc} {summary.brew_formulae or 0} formulae installed", file=out)
        print(f"  {s.green}✓{s.nc} {summary.brew_casks or 0} casks installed", file=out)
    else:
        print(f"  {s.red}✗{s.nc} Homebrew not installed", file=out)
    return 0


def cmd_diff(paths: GroundhogPaths, *, out: TextIO | None = None) -> int:
    """Compare repo configs against live files in `$HOME`."""
    out = out or sys.stdout
    s = Style(out)
    print(f"{s.blue}Comparing repo with home directory...{s.nc}\n", file=out)

    for pkg in STOW_PACKAGES:
        for rel in get_targets(paths, pkg):
            repo_file = paths.repo_dir / pkg / rel
            home_file = paths.home_dir / rel
            if not repo_file.exists():
                continue
            print(f"{s.yellow}=== {rel} ({pkg}) ==={s.nc}", file=out)
            if home_file.is_symlink():
                if is_managed_link(paths, home_file):
                    print(f"{s.green}✓ Linked to repo{s.nc}", file=out)
                else:
                    print(f"{s.red}⚠ Linked elsewhere: {os.readlink(home_file)}{s.nc}", file=out)
            elif home_file.exists():
                if home_file.is_dir():
                    print(f"{s.red}Directory exists (not linked){s.nc}", file=out)
                elif filecmp.cmp(home_file, repo_file, shallow=False):
                    print(f"{s.green}✓ Identical{s.nc}", file=out)
                else:
                    print(f"{s.red}✗ Different:{s.nc}", file=out)
                    diff_lines = list(
                        difflib.unified_diff(
                            home_file.read_text(encoding="utf-8", errors="replace").splitlines(),
                            repo_file.read_text(encoding="utf-8", errors="replace").splitlines(),
                            fromfile=str(home_file),
                            tofile=str(repo_file),
                            lineterm="",
                        )
                    )
                    for line in diff_lines[:30]:
                        print(line, file=out)
            else:
                print(f"{s.yellow}○ Not present in home{s.nc}", file=out)
            print(file=out)

    print(f"{s.yellow}=== Manual & Custom Symlinks ==={s.nc}", file=out)
    for src, target in manual_links(paths):
        if target.is_symlink():
            if Path(os.readlink(target)) == src:
                print(f"  {s.green}✓{s.nc} {target}", file=out)
            else:
                print(f"  {s.red}⚠{s.nc} {target} -> {os.readlink(target)}", file=out)
        elif target.exists():
            print(f"  {s.red}✗{s.nc} {target} (exists but not linked)", file=out)
        else:
            print(f"  {s.yellow}○{s.nc} {target} (missing)", file=out)
    print(file=out)

    copies = app_copies(paths)
    if copies:
        print(f"{s.yellow}=== App-managed copies ==={s.nc}", file=out)
        for src, target in copies:
            _app_copy_check(src, target, seed=False, style=s, out=out)
            if (
                target.is_file()
                and not target.is_symlink()
                and src.is_file()
                and not filecmp.cmp(src, target, shallow=False)
            ):
                diff_lines = list(
                    difflib.unified_diff(
                        src.read_text(encoding="utf-8", errors="replace").splitlines(),
                        target.read_text(encoding="utf-8", errors="replace").splitlines(),
                        fromfile=str(src),
                        tofile=str(target),
                        lineterm="",
                    )
                )
                for line in diff_lines[:40]:
                    print(line, file=out)
        print(file=out)
    return 0


def cmd_capture(paths: GroundhogPaths, *, out: TextIO | None = None) -> int:
    """Copy app-managed files from `$HOME` back into the repo/overlay."""
    out = out or sys.stdout
    s = Style(out)
    print(f"{s.blue}Capturing app-managed files into the repo...{s.nc}\n", file=out)
    copies = app_copies(paths)
    if not copies:
        print("  (no app-managed copies configured)", file=out)
        return 0
    for src, target in copies:
        if target.is_file() and not target.is_symlink():
            if src.is_file() and filecmp.cmp(target, src, shallow=False):
                print(f"  {s.green}✓{s.nc} {src} (unchanged)", file=out)
            else:
                src.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, src)
                print(f"  {s.green}→{s.nc} {src} (updated; review with git diff)", file=out)
        else:
            print(f"  {s.yellow}○{s.nc} {target} (not a plain file; skipped)", file=out)
    return 0


def cmd_link(
    paths: GroundhogPaths,
    *,
    skip_hooks: bool = False,
    skip_tmux: bool = False,
    skip_bat: bool = False,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Stow configs, link manual/custom files, install hooks, and refresh tmux/bat."""
    out = out or sys.stdout
    err = err or sys.stderr
    s = Style(out)
    print(f"{s.blue}Linking dotfiles...{s.nc}\n", file=out)

    if not shutil.which("stow"):
        print(f"{s.red}Error: stow is not installed.{s.nc}", file=err)
        print(f"Install it with: {s.yellow}brew install stow{s.nc}", file=err)
        return 1

    paths.backup_dir.mkdir(parents=True, exist_ok=True)
    print(f"{s.blue}Stowing config packages...{s.nc}\n", file=out)
    for pkg in STOW_PACKAGES:
        pkg_dir = paths.repo_dir / pkg
        if not pkg_dir.is_dir():
            continue
        print(f"  Stowing {s.green}{pkg}{s.nc}...", file=out)
        for entry in pkg_dir.rglob("*"):
            rel = entry.relative_to(pkg_dir)
            target = paths.home_dir / rel
            if target.is_symlink() and not target.exists():
                print(f"    {s.yellow}Removing broken link{s.nc}: {rel}", file=out)
                target.unlink()

        stow_cmd = ["stow", "-v", "-t", str(paths.home_dir)]
        if pkg in NO_FOLDING_PACKAGES:
            stow_cmd.append("--no-folding")
        stow_cmd.append(pkg)

        proc = subprocess.run(
            stow_cmd,
            cwd=paths.repo_dir,
            capture_output=True,
            text=True,
            check=False,
        )
        combined = (proc.stdout + proc.stderr).strip()
        if proc.returncode != 0:
            if combined:
                print(combined, file=err)
            print(
                f"  {s.red}Failed to stow {pkg}; resolve the conflict explicitly.{s.nc}",
                file=err,
            )
            return 1
        if combined:
            for line in combined.splitlines():
                print(f"    {line}", file=out)

    print(f"\n{s.blue}Creating manual & custom symlinks...{s.nc}\n", file=out)
    for src, target in manual_links(paths):
        if not src.exists():
            print(f"  {s.yellow}○{s.nc} Skipping missing source: {src}", file=out)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink() and Path(os.readlink(target)) == src:
            print(f"  {s.green}✓{s.nc} {target} (already linked)", file=out)
            continue
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            backup_name = f"{target.name}.backup.{int(time.time())}"
            backup_path = paths.backup_dir / backup_name
            print(f"  {s.yellow}Backing up{s.nc} {target} -> {backup_path}", file=out)
            shutil.move(str(target), str(backup_path))
        target.symlink_to(src)
        print(f"  {s.green}→{s.nc} {target}", file=out)

    copies = app_copies(paths)
    if copies:
        print(f"\n{s.blue}Checking app-managed copies...{s.nc}\n", file=out)
        for src, target in copies:
            if not src.exists():
                print(f"  {s.yellow}○{s.nc} Skipping missing source: {src}", file=out)
                continue
            _app_copy_check(src, target, seed=True, style=s, out=out)

    if not skip_hooks:
        print(f"\n{s.blue}Installing repository hooks...{s.nc}\n", file=out)
        _install_repo_hooks(paths.repo_dir, "groundhog", style=s, out=out)
        if paths.custom_dir.is_dir():
            _install_repo_hooks(paths.custom_dir, "custom/", style=s, out=out)

    if not skip_tmux:
        print(f"\n{s.blue}Setting up tmux plugins...{s.nc}\n", file=out)
        if shutil.which("tmux") and shutil.which("git"):
            tpm_dir = paths.home_dir / ".tmux" / "plugins" / "tpm"
            ensure_git_checkout(TPM_REPO, tpm_dir, TPM_COMMIT)
            print(f"  {s.green}✓{s.nc} TPM @ {TPM_COMMIT[:12]}", file=out)
            install_script = tpm_dir / "bin" / "install_plugins"
            proc = subprocess.run(
                [str(install_script)],
                env={**os.environ, "HOME": str(paths.home_dir)},
                capture_output=True,
                text=True,
                check=False,
            )
            combined = (proc.stdout + proc.stderr).strip()
            if proc.returncode != 0:
                if combined:
                    print(combined, file=err)
                print(f"  {s.red}Tmux plugin installation failed.{s.nc}", file=err)
                return 1
            for line in combined.splitlines():
                print(f"    {line}", file=out)
        else:
            print(f"  {s.yellow}⚠{s.nc} Skipping tmux plugins (tmux/git not installed)", file=out)

    if not skip_bat:
        print(f"\n{s.blue}Rebuilding bat theme cache...{s.nc}", file=out)
        if shutil.which("bat"):
            proc = subprocess.run(
                ["bat", "cache", "--build"],
                env={**os.environ, "HOME": str(paths.home_dir)},
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            if proc.returncode == 0:
                print(f"  {s.green}✓{s.nc} Done", file=out)
            else:
                print(f"  {s.red}Bat cache rebuild failed: {proc.stderr.strip()}{s.nc}", file=err)
                return 1
        else:
            print(f"  {s.yellow}⚠{s.nc} Skipping bat cache (bat not installed)", file=out)

    print(
        f"\n{s.green}Linking complete!{s.nc} Restart your shell: "
        f"{s.yellow}exec nu{s.nc} (or {s.yellow}exec zsh{s.nc})",
        file=out,
    )
    print(f"Then reload tmux: {s.yellow}tmux source ~/.tmux.conf{s.nc}", file=out)
    return 0


def cmd_unlink(
    paths: GroundhogPaths,
    *,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Unstow all Stow-managed packages cleanly."""
    out = out or sys.stdout
    err = err or sys.stderr
    s = Style(out)
    if not shutil.which("stow"):
        print(f"{s.red}Error: stow is not installed.{s.nc}", file=err)
        return 1
    print(f"{s.blue}Unstowing config packages...{s.nc}\n", file=out)
    for pkg in STOW_PACKAGES:
        if not (paths.repo_dir / pkg).is_dir():
            continue
        proc = subprocess.run(
            ["stow", "-D", "-t", str(paths.home_dir), pkg],
            cwd=paths.repo_dir,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            print(f"  {s.red}✗{s.nc} {pkg}: {(proc.stdout + proc.stderr).strip()}", file=err)
            return 1
        print(f"  {s.green}✓{s.nc} unstowed {pkg}", file=out)
    return 0


def cmd_brew(paths: GroundhogPaths, *, out: TextIO | None = None) -> int:
    """Install Homebrew (if absent) and apply core + overlay + local Brewfiles."""
    out = out or sys.stdout
    s = Style(out)
    print(f"{s.blue}Installing Homebrew packages...{s.nc}\n", file=out)

    if not shutil.which("brew"):
        print(f"{s.yellow}Installing Homebrew from pinned installer...{s.nc}", file=out)
        script = subprocess.check_output(["curl", "-fsSL", HOMEBREW_INSTALL_URL], text=True)
        subprocess.run(["/bin/bash", "-c", script], check=True)
        for candidate in ("/opt/homebrew/bin", "/usr/local/bin"):
            if (Path(candidate) / "brew").is_file():
                os.environ["PATH"] = f"{candidate}:{os.environ.get('PATH', '')}"
                break

    for label, brewfile in (
        ("core packages from homebrew/.Brewfile", paths.homebrew_brewfile),
        ("private overlay packages from custom/Brewfile", paths.custom_brewfile),
        ("machine-specific packages from .Brewfile.local", paths.local_brewfile),
    ):
        if brewfile.is_file():
            print(f"{s.green}Installing {label}...{s.nc}", file=out)
            subprocess.run(
                ["brew", "bundle", "install", "--no-upgrade", f"--file={brewfile}"],
                check=True,
            )
    return 0


def cmd_apply(paths: GroundhogPaths, *, out: TextIO | None = None) -> int:
    """Run Homebrew sync followed by dotfile linking."""
    rc = cmd_brew(paths, out=out)
    if rc != 0:
        return rc
    return cmd_link(paths, out=out)


def cmd_init_custom(
    paths: GroundhogPaths,
    *,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Scaffold a new private overlay repository in `custom/` from `custom.example/`."""
    out = out or sys.stdout
    err = err or sys.stderr
    s = Style(out)
    if paths.custom_dir.exists():
        print(
            f"{s.red}Error:{s.nc} {paths.custom_dir} already exists. Refusing to overwrite.",
            file=err,
        )
        return 1
    if not paths.custom_example_dir.is_dir():
        print(
            f"{s.red}Error:{s.nc} {paths.custom_example_dir} template directory not found.",
            file=err,
        )
        return 1

    shutil.copytree(paths.custom_example_dir, paths.custom_dir)
    subprocess.run(
        ["git", "-C", str(paths.custom_dir), "init", "-b", "main"],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    _install_repo_hooks(paths.custom_dir, "custom/", style=s, out=out)

    print(f"{s.green}Initialised private overlay repo at:{s.nc} {paths.custom_dir}", file=out)
    print("\nNext steps:", file=out)
    print(
        f"  1. Customise config.yml, Brewfile, gitconfig, and links.conf inside {paths.custom_dir}",
        file=out,
    )
    print("  2. Validate with: ./groundhog verify-custom", file=out)
    print("  3. Commit and push to your own private GitHub repository:", file=out)
    print(f"       cd {paths.custom_dir}", file=out)
    print("       git add -A && git commit -m 'Initial private overlay'", file=out)
    print("       gh repo create groundhog-private --private --source=. --push", file=out)
    return 0


def cmd_verify_custom(
    paths: GroundhogPaths,
    *,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Validate the private `custom/` overlay (YAML, manifests, SSH keys, hooks)."""
    out = out or sys.stdout
    err = err or sys.stderr
    s = Style(out)

    if not paths.custom_dir.is_dir():
        print(
            f"{s.yellow}No custom/ overlay present at {paths.custom_dir}; skipping.{s.nc}",
            file=out,
        )
        return 0

    print(f"{s.blue}Verifying custom/ overlay ({paths.custom_dir})...{s.nc}\n", file=out)
    errors: list[str] = []

    # 1. Validate manifests: links.conf & copies.conf
    for manifest_name in ("links.conf", "copies.conf"):
        manifest_path = paths.custom_dir / manifest_name
        if not manifest_path.is_file():
            continue
        try:
            entries = load_custom_manifest(manifest_path, paths.custom_dir, paths.home_dir)
        except ValueError as exc:
            errors.append(f"{manifest_name}: {exc}")
            continue
        for src, _target in entries:
            if not src.exists():
                rel_src = src.relative_to(paths.custom_dir)
                errors.append(f"{manifest_name}: missing source {rel_src}")
        print(f"  {s.green}✓{s.nc} {manifest_name} ({len(entries)} entries checked)", file=out)

    # 2. Validate YAML files with yamllint (if installed)
    yaml_files = [
        p
        for p in (
            paths.custom_dir / "config.yml",
            paths.custom_dir / "tasks.yml",
            paths.custom_dir / ".pre-commit-config.yaml",
        )
        if p.is_file()
    ]
    if yaml_files:
        if shutil.which("yamllint"):
            yamllint_cmd = ["yamllint"]
            yamllint_cfg = paths.repo_dir / ".yamllint"
            if yamllint_cfg.is_file():
                yamllint_cmd.extend(["-c", str(yamllint_cfg)])
            yamllint_cmd.extend(str(p) for p in yaml_files)
            proc = subprocess.run(
                yamllint_cmd,
                cwd=paths.repo_dir,
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                errors.append(f"yamllint failed:\n{(proc.stdout + proc.stderr).strip()}")
            else:
                print(
                    f"  {s.green}✓{s.nc} YAML lint ({', '.join(p.name for p in yaml_files)})",
                    file=out,
                )
        else:
            print(f"  {s.yellow}⚠{s.nc} yamllint not installed; skipping YAML lint", file=out)

    # 3. Validate SSH public keys & authorized_keys with ssh-keygen -lf
    if shutil.which("ssh-keygen"):
        key_files: list[Path] = []
        for candidate in paths.custom_dir.rglob("*"):
            if ".git" in candidate.parts or not candidate.is_file():
                continue
            if candidate.name == "authorized_keys" or candidate.suffix == ".pub":
                key_files.append(candidate)
        for key_file in sorted(key_files):
            proc = subprocess.run(
                ["ssh-keygen", "-lf", str(key_file)],
                capture_output=True,
                text=True,
                check=False,
            )
            rel = key_file.relative_to(paths.custom_dir)
            if proc.returncode != 0:
                errors.append(f"Invalid SSH key file {rel}: {proc.stderr.strip()}")
            else:
                print(f"  {s.green}✓{s.nc} SSH keys valid: {rel}", file=out)

    # 4. Validate allowed_signers format (principal + key-type + key-blob)
    for signers in sorted(paths.custom_dir.rglob("allowed_signers")):
        if ".git" in signers.parts or not signers.is_file():
            continue
        rel = signers.relative_to(paths.custom_dir)
        bad_lines: list[int] = []
        for idx, raw in enumerate(signers.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parts = stripped.split()
            if len(parts) < 3 or not (
                parts[1].startswith(("ssh-", "ecdsa-", "sk-")) or parts[1].startswith("namespaces=")
            ):
                bad_lines.append(idx)
        if bad_lines:
            errors.append(f"Malformed {rel} line(s): {bad_lines}")
        else:
            print(f"  {s.green}✓{s.nc} allowed_signers format valid: {rel}", file=out)

    # 5. Check custom/.git hook presence
    if (paths.custom_dir / ".git").exists() and (
        paths.custom_dir / ".pre-commit-config.yaml"
    ).is_file():
        hook_path = paths.custom_dir / ".git" / "hooks" / "pre-commit"
        if hook_path.is_file():
            print(f"  {s.green}✓{s.nc} custom/ pre-commit hook installed", file=out)
        else:
            print(
                f"  {s.yellow}⚠{s.nc} custom/ pre-commit hook not installed "
                "(run ./groundhog link to install)",
                file=out,
            )

    if errors:
        print(f"\n{s.red}Custom overlay verification failed:{s.nc}", file=err)
        for item in errors:
            print(f"  - {item}", file=err)
        return 1

    print(f"\n{s.green}Custom overlay verification passed.{s.nc}", file=out)
    return 0


def cmd_ansible(
    paths: GroundhogPaths,
    extra_args: list[str],
    *,
    check: bool = False,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Run the Ansible playbook with a single-auth session-scoped sudo keepalive."""
    out = out or sys.stdout
    err = err or sys.stderr
    s = Style(out)

    if not shutil.which("ansible-playbook"):
        print(f"{s.red}Error: ansible-playbook is not installed.{s.nc}", file=err)
        print(f"Run {s.yellow}bash ansible/bootstrap.sh{s.nc} first.", file=err)
        return 1

    args = list(extra_args)
    if check:
        if "--check" not in args:
            args.append("--check")
        if "--diff" not in args:
            args.append("--diff")

    stop_event = threading.Event()
    sudoers_installed = False

    def cleanup() -> None:
        stop_event.set()
        if sudoers_installed and ANSIBLE_SUDOERS_TMP.exists():
            subprocess.run(
                ["sudo", "-n", "rm", "-f", str(ANSIBLE_SUDOERS_TMP)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        subprocess.run(
            ["sudo", "-k"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _handle_signal(signum: int, _frame: object) -> None:
        cleanup()
        raise SystemExit(128 + signum)

    prev_int = signal.signal(signal.SIGINT, _handle_signal)
    prev_term = signal.signal(signal.SIGTERM, _handle_signal)

    try:
        print(f"{s.blue}Preparing temporary session-scoped sudo for Ansible...{s.nc}", file=out)
        setup_script = (
            "set -eu; "
            "umask 0377; "
            "tmp=$(mktemp /etc/sudoers.d/.groundhog-ansible.XXXXXX); "
            'trap "rm -f \\"$tmp\\"" EXIT; '
            'printf "Defaults timestamp_type=global\\n" > "$tmp"; '
            'chmod 0440 "$tmp"; '
            '/usr/sbin/visudo -cf "$tmp" >/dev/null; '
            'chown root:wheel "$tmp"; '
            'mv "$tmp" "$1"; '
            "trap - EXIT"
        )
        subprocess.run(
            ["sudo", "sh", "-c", setup_script, "_", str(ANSIBLE_SUDOERS_TMP)],
            check=True,
        )
        sudoers_installed = True

        # Stamp the global ticket so setsid-detached Ansible workers inherit it.
        subprocess.run(["sudo", "-v"], check=True)

        def _keepalive() -> None:
            while not stop_event.wait(30):
                res = subprocess.run(
                    ["sudo", "-n", "-v"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
                if res.returncode != 0:
                    return

        thread = threading.Thread(target=_keepalive, daemon=True)
        thread.start()

        proc = subprocess.run(
            ["ansible-playbook", str(paths.ansible_playbook), *args],
            cwd=paths.repo_dir,
            check=False,
        )
        return proc.returncode
    finally:
        signal.signal(signal.SIGINT, prev_int)
        signal.signal(signal.SIGTERM, prev_term)
        cleanup()
