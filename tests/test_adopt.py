"""Tests for groundhog adopt and groundhog clean."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from groundhog.adopt import AdoptPlan, cmd_adopt, cmd_clean, scan_adopt
from groundhog.cli import main as cli_main
from groundhog.config import GroundhogPaths


def _make_fake_repo(tmp_path: Path) -> GroundhogPaths:
    repo = tmp_path / "repo"
    home = tmp_path / "home"
    home.mkdir()
    (repo / "zsh").mkdir(parents=True)
    (repo / "zsh" / ".zshrc").write_text("# groundhog zshrc\n", encoding="utf-8")
    (repo / "git").mkdir(parents=True)
    (repo / "git" / ".gitconfig").write_text(
        "[include]\n    path = ~/.gitconfig.custom\n", encoding="utf-8"
    )
    (repo / "ssh" / ".ssh").mkdir(parents=True)
    (repo / "ssh" / ".ssh" / "config").write_text("Host *\n  ForwardAgent no\n", encoding="utf-8")
    (repo / "homebrew").mkdir(parents=True)
    (repo / "homebrew" / ".Brewfile").write_text('brew "git"\n', encoding="utf-8")
    (repo / "custom.example").mkdir(parents=True)
    (repo / "custom.example" / "config.yml").write_text("---\n", encoding="utf-8")
    (repo / "custom.example" / "Brewfile").write_text("# custom brewfile\n", encoding="utf-8")
    (repo / "custom.example" / "gitconfig").write_text("# custom gitconfig\n", encoding="utf-8")
    (repo / "custom.example" / ".gitignore").write_text(".DS_Store\n", encoding="utf-8")
    return GroundhogPaths(repo_dir=repo, home_dir=home)


def test_scan_adopt_detects_conflicts_identity_and_secrets(tmp_path: Path) -> None:
    paths = _make_fake_repo(tmp_path)
    (paths.home_dir / ".zshrc").write_text(
        'export PATH="$HOME/bin:$PATH"\nexport MY_CUSTOM_API_KEY="placeholder-value"\n',
        encoding="utf-8",
    )
    (paths.home_dir / ".gitconfig").write_text(
        "[user]\n"
        "    name = Jane Dev\n"
        "    email = jane@example.invalid\n"
        "    signingkey = ~/.ssh/id_ed25519.pub\n",
        encoding="utf-8",
    )
    (paths.home_dir / ".ssh").mkdir()
    (paths.home_dir / ".ssh" / "config").write_text(
        "Host lab\n  HostName 10.0.0.5\n", encoding="utf-8"
    )

    plan = scan_adopt(paths, include_system=False)
    assert ".zshrc" in plan.conflicts
    assert ".gitconfig" in plan.conflicts
    assert ".ssh/config" in plan.conflicts
    assert plan.git_identity["user.name"] == "Jane Dev"
    assert plan.git_identity["user.signingkey"] == "~/.ssh/id_ed25519.pub"
    assert plan.ssh_config_present is True
    assert plan.zshrc_present is True
    assert len(plan.secret_warnings) == 1
    assert ".zshrc:2" in plan.secret_warnings[0]


def test_adopt_apply_snapshots_and_skips_secret_zshrc(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    paths = _make_fake_repo(tmp_path)
    (paths.home_dir / ".zshrc").write_text('export API_TOKEN="secret"\n', encoding="utf-8")
    (paths.home_dir / ".gitconfig").write_text(
        "[user]\n"
        "    name = Jane Dev\n"
        "    email = jane@example.invalid\n"
        "    signingkey = ~/.ssh/id_sign.pub\n",
        encoding="utf-8",
    )
    (paths.home_dir / ".ssh").mkdir()
    (paths.home_dir / ".ssh" / "config").write_text(
        "Host lab\n  HostName 10.0.0.5\n", encoding="utf-8"
    )

    fake_plan = AdoptPlan(
        conflicts=[".gitconfig", ".ssh/config", ".zshrc"],
        extra_brew_lines=['brew "ripgrep"', 'cask "linear-linear"'],
        dock_apps=["/Applications/Ghostty.app", "/Applications/Safari.app"],
        git_identity={
            "user.name": "Jane Dev",
            "user.email": "jane@example.invalid",
            "user.signingkey": "~/.ssh/id_sign.pub",
        },
        ssh_config_present=True,
        zshrc_present=True,
        secret_warnings=["~/.zshrc:1 looks like a secret/token assignment"],
    )
    monkeypatch.setattr("groundhog.adopt.scan_adopt", lambda *a, **kw: fake_plan)

    rc = cmd_adopt(paths, apply=True, as_json=True)
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    backup_dir = Path(payload["backup_dir"])
    assert (backup_dir / "manifest.json").is_file()
    assert (backup_dir / "files" / ".zshrc").is_file()
    assert 'brew "ripgrep"' in paths.custom_brewfile.read_text(encoding="utf-8")
    assert "/Applications/Ghostty.app" in (paths.custom_dir / "config.yml").read_text(
        encoding="utf-8"
    )
    assert "Jane Dev" in (paths.custom_dir / "gitconfig").read_text(encoding="utf-8")
    assert "id_sign.pub" in (paths.home_dir / ".gitconfig.local").read_text(encoding="utf-8")
    assert "Host lab" in (paths.home_dir / ".ssh" / "config.local").read_text(encoding="utf-8")
    assert not (paths.home_dir / ".zshrc.local").exists(), (
        "must not copy zshrc with secret warnings"
    )


def test_clean_removes_managed_links_and_restores_backup(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    paths = _make_fake_repo(tmp_path)
    (paths.home_dir / ".zshrc").write_text("# my original zshrc\n", encoding="utf-8")
    (paths.home_dir / ".ssh").mkdir()
    (paths.home_dir / ".ssh" / "config").write_text("Host mybox\n", encoding="utf-8")

    # Apply adopt to create a real backup manifest.
    assert cmd_adopt(paths, apply=True, include_system=False) == 0

    # Simulate Groundhog replacing files with managed links + wrappers.
    (paths.home_dir / ".zshrc").unlink()
    (paths.home_dir / ".zshrc").symlink_to(paths.repo_dir / "zsh" / ".zshrc")
    (paths.home_dir / ".ssh" / "config").unlink()
    (paths.home_dir / ".ssh" / "config").symlink_to(paths.repo_dir / "ssh" / ".ssh" / "config")
    paths.local_bin_dir.mkdir(parents=True, exist_ok=True)
    wrapper = paths.local_bin_dir / "agent-git"
    wrapper.write_text("#!/usr/bin/env bash\n# Managed by Groundhog\n", encoding="utf-8")

    # Stub cmd_unlink so stow isn't required in unit tests.
    monkeypatch.setattr("groundhog.adopt.cmd_unlink", lambda _: 0)

    assert cmd_clean(paths, restore_latest=True, dry_run=True) == 0
    assert wrapper.exists()

    assert cmd_clean(paths, restore_latest=True, dry_run=False) == 0
    assert not wrapper.exists()
    assert not (paths.home_dir / ".zshrc").is_symlink()
    assert (paths.home_dir / ".zshrc").read_text(encoding="utf-8") == "# my original zshrc\n"
    assert not (paths.home_dir / ".ssh" / "config").is_symlink()
    assert (paths.home_dir / ".ssh" / "config").read_text(encoding="utf-8") == "Host mybox\n"


def test_cli_adopt_json_flag(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    paths = _make_fake_repo(tmp_path)
    assert cli_main(["adopt", "--json"], paths=paths) == 0
    data = json.loads(capsys.readouterr().out)
    assert "conflicts" in data and "secret_warnings" in data
    assert isinstance(subprocess.CompletedProcess([], 0), subprocess.CompletedProcess)
