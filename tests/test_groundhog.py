"""Behavioural and unit tests for the Groundhog Python CLI, helpers, and TUI."""

from __future__ import annotations

import io
import json
import shutil
from pathlib import Path

import pytest

from groundhog.cli import main
from groundhog.config import STOW_PACKAGES, GroundhogPaths, expand_home, parse_manifest_lines
from groundhog.helpers import (
    extract_last_command_output,
    merge_claude_settings,
    merge_claude_settings_file,
)
from groundhog.ops import (
    cmd_ansible,
    cmd_capture,
    cmd_diff,
    cmd_init_custom,
    cmd_link,
    cmd_status,
    cmd_unlink,
    cmd_verify_custom,
    get_targets,
)
from groundhog.tui import MenuState, build_menu_items

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_expand_home_tilde_and_env_var(tmp_path: Path) -> None:
    assert expand_home("~/.ssh/config", tmp_path) == tmp_path / ".ssh/config"
    assert expand_home("$HOME/.aws/config", tmp_path) == tmp_path / ".aws/config"
    assert expand_home("~", tmp_path) == tmp_path


def test_parse_manifest_lines_valid_and_invalid(tmp_path: Path) -> None:
    custom = tmp_path / "custom"
    home = tmp_path / "home"
    text = """
    # comment line
    gitconfig:~/.gitconfig.custom
    aws/.aws/config:$HOME/.aws/config
    """
    entries = parse_manifest_lines(text, custom, home)
    assert entries == [
        (custom / "gitconfig", home / ".gitconfig.custom"),
        (custom / "aws/.aws/config", home / ".aws/config"),
    ]

    with pytest.raises(ValueError, match="expected 'src:target'"):
        parse_manifest_lines("not-a-valid-line", custom, home)


def test_every_stow_package_has_targets() -> None:
    paths = GroundhogPaths(repo_dir=REPO_ROOT, home_dir=Path.home())
    for pkg in STOW_PACKAGES:
        targets = get_targets(paths, pkg)
        assert targets, f"STOW_PACKAGES entry {pkg!r} returned no targets"


def test_extract_last_command_output_oh_my_posh_and_plain() -> None:
    omp_lines = [
        "mac dave ~/code \uf105 echo hello",
        "hello",
        "world",
        "mac dave ~/code \uf105 ",
    ]
    assert extract_last_command_output(omp_lines) == "hello\nworld"

    plain_lines = [
        "dave@mac:~/code$ ls",
        "file1.txt",
        "file2.txt",
        "dave@mac:~/code$ ",
    ]
    assert extract_last_command_output(plain_lines) == "file1.txt\nfile2.txt"

    assert extract_last_command_output(["only one prompt \uf105 "]) == ""


def test_merge_claude_settings_preserves_user_prefs_and_is_idempotent(tmp_path: Path) -> None:
    baseline = {
        "sandbox": {"enabled": True, "allowUnsandboxedCommands": False},
        "permissions": {
            "deny": [
                "Read(~/.ssh/**)",
                "Edit(~/.ssh/**)",
                "Bash(git push --force:*)",
            ]
        },
        "hooks": {"PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command"}]}]},
    }
    current = {
        "theme": "dark",
        "permissions": {"deny": ["Read(~/.custom-secret/**)", "Read(~/.ssh/**)"]},
        "sandbox": {"enabled": False, "allowUnsandboxedCommands": True},
    }

    merged, changed = merge_claude_settings(current, baseline)
    assert changed is True
    assert merged["theme"] == "dark"
    assert merged["sandbox"] == {"enabled": True, "allowUnsandboxedCommands": False}
    assert merged["permissions"]["deny"] == sorted(
        [
            "Bash(git push --force:*)",
            "Edit(~/.ssh/**)",
            "Read(~/.custom-secret/**)",
            "Read(~/.ssh/**)",
        ]
    )
    assert merged["hooks"]["PostToolUse"] == baseline["hooks"]["PostToolUse"]

    # Second merge is a no-op
    merged2, changed2 = merge_claude_settings(merged, baseline)
    assert changed2 is False
    assert merged2 == merged

    # File-level helper writes mode 0600 and preserves existing PostToolUse hooks
    baseline_path = tmp_path / "baseline.json"
    target_path = tmp_path / "settings.json"
    baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
    target_path.write_text(
        json.dumps({"hooks": {"PostToolUse": [{"matcher": "Custom"}]}}),
        encoding="utf-8",
    )
    assert merge_claude_settings_file(target_path, baseline_path) is True
    assert (target_path.stat().st_mode & 0o777) == 0o600
    saved = json.loads(target_path.read_text(encoding="utf-8"))
    assert saved["hooks"]["PostToolUse"] == [{"matcher": "Custom"}]
    assert merge_claude_settings_file(target_path, baseline_path) is False


def test_init_custom_and_verify_custom_end_to_end(tmp_path: Path) -> None:
    repo = tmp_path / "groundhog"
    home = tmp_path / "home"
    repo.mkdir()
    home.mkdir()
    shutil.copytree(REPO_ROOT / "custom.example", repo / "custom.example")
    if (REPO_ROOT / ".yamllint").is_file():
        shutil.copy2(REPO_ROOT / ".yamllint", repo / ".yamllint")

    paths = GroundhogPaths(repo_dir=repo, home_dir=home)
    out = io.StringIO()
    err = io.StringIO()

    rc = cmd_init_custom(paths, out=out, err=err)
    assert rc == 0, err.getvalue()
    assert (repo / "custom" / ".git").is_dir()
    assert (repo / "custom" / "config.yml").is_file()

    # Refuses to overwrite existing custom/
    assert cmd_init_custom(paths, out=out, err=err) == 1

    # Fresh scaffold passes verification
    out2 = io.StringIO()
    err2 = io.StringIO()
    assert cmd_verify_custom(paths, out=out2, err=err2) == 0, err2.getvalue()

    # Missing source in links.conf fails verification
    (repo / "custom" / "links.conf").write_text("does-not-exist:~/.foo\n", encoding="utf-8")
    err3 = io.StringIO()
    assert cmd_verify_custom(paths, out=io.StringIO(), err=err3) == 1
    assert "missing source does-not-exist" in err3.getvalue()

    # Malformed allowed_signers fails verification
    (repo / "custom" / "links.conf").write_text("", encoding="utf-8")
    (repo / "custom" / "allowed_signers").write_text("bad-line-only\n", encoding="utf-8")
    err4 = io.StringIO()
    assert cmd_verify_custom(paths, out=io.StringIO(), err=err4) == 1
    assert "Malformed allowed_signers" in err4.getvalue()


@pytest.mark.skipif(not shutil.which("stow"), reason="GNU stow not installed")
def test_link_status_diff_capture_unlink_in_isolated_home(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    home = tmp_path / "home"
    repo.mkdir()
    home.mkdir()

    # Create a minimal realistic repo layout with stow packages, manual link, and custom overlay
    (repo / "zsh").mkdir()
    (repo / "zsh" / ".zshrc").write_text("# zshrc\n", encoding="utf-8")
    (repo / "zsh" / ".zprofile").write_text("# zprofile\n", encoding="utf-8")
    (repo / "git" / ".config" / "git" / "template" / "hooks").mkdir(parents=True)
    (repo / "git" / ".gitconfig").write_text("[init]\n\tdefaultBranch = main\n", encoding="utf-8")
    (repo / "git" / ".config" / "git" / "template" / "hooks" / "pre-commit").write_text(
        "#!/usr/bin/env bash\n",
        encoding="utf-8",
    )
    (repo / "ssh" / ".ssh").mkdir(parents=True)
    (repo / "ssh" / ".ssh" / "config").write_text("Host *\n", encoding="utf-8")
    (repo / "ghostty" / ".config" / "ghostty").mkdir(parents=True)
    (repo / "ghostty" / ".config" / "ghostty" / "config").write_text(
        "window-save-state = never\n",
        encoding="utf-8",
    )
    (repo / "atuin" / ".config" / "atuin").mkdir(parents=True)
    (repo / "atuin" / ".config" / "atuin" / "config.toml").write_text(
        "auto_sync = false\n",
        encoding="utf-8",
    )
    (repo / "groundhog").write_text("#!/usr/bin/env bash\n", encoding="utf-8")

    # Custom overlay with one link and one app-managed copy
    custom = repo / "custom"
    custom.mkdir()
    (custom / "gitconfig").write_text("[user]\n\tname = Test\n", encoding="utf-8")
    (custom / "links.conf").write_text("gitconfig:~/.gitconfig.custom\n", encoding="utf-8")
    (custom / "app.json").write_text('{"v": 1}\n', encoding="utf-8")
    (custom / "copies.conf").write_text("app.json:~/.config/app/app.json\n", encoding="utf-8")

    # Pre-existing ~/.zprofile (stowed) and ~/.ssh/config (manual) should both be backed up
    (home / ".zprofile").write_text("# pre-existing zprofile\n", encoding="utf-8")
    (home / ".ssh").mkdir()
    (home / ".ssh" / "config").write_text("# old config\n", encoding="utf-8")

    paths = GroundhogPaths(repo_dir=repo, home_dir=home)

    rc = cmd_link(
        paths,
        skip_hooks=True,
        skip_tmux=True,
        skip_bat=True,
        out=io.StringIO(),
        err=io.StringIO(),
    )
    assert rc == 0
    assert (home / ".zshrc").is_symlink()
    assert (home / ".zprofile").is_symlink()
    assert list((home / ".backups").glob(".zprofile.backup.*"))
    assert (home / ".gitconfig").is_symlink()
    assert not (home / ".config" / "git").is_symlink()  # --no-folding verified!
    assert (home / ".ssh" / "config").is_symlink()
    assert list((home / ".backups").glob("config.backup.*"))
    assert (home / ".local" / "bin" / "groundhog").is_symlink()
    assert (home / ".gitconfig.custom").is_symlink()
    assert (home / ".config" / "ghostty").is_symlink()
    assert (home / ".config" / "app" / "app.json").read_text(encoding="utf-8") == '{"v": 1}\n'

    # Re-running cmd_link must be idempotent and never move files through folded dir symlinks
    rc2 = cmd_link(
        paths,
        skip_hooks=True,
        skip_tmux=True,
        skip_bat=True,
        out=io.StringIO(),
        err=io.StringIO(),
    )
    assert rc2 == 0
    assert (repo / "ghostty" / ".config" / "ghostty" / "config").is_file()
    assert (home / ".config" / "ghostty" / "config").is_file()

    # Simulate app modifying copy, then capture back into custom/
    (home / ".config" / "app" / "app.json").write_text('{"v": 2}\n', encoding="utf-8")
    assert cmd_capture(paths, out=io.StringIO()) == 0
    assert (custom / "app.json").read_text(encoding="utf-8") == '{"v": 2}\n'

    # Status and diff run cleanly (including folded packages like atuin)
    status_out = io.StringIO()
    assert cmd_status(paths, out=status_out) == 0
    assert ".zshrc" in status_out.getvalue()
    assert "✓ .config/atuin/config.toml" in status_out.getvalue()

    diff_out = io.StringIO()
    assert cmd_diff(paths, out=diff_out) == 0

    # Unlink cleans up stowed symlinks
    assert cmd_unlink(paths, out=io.StringIO(), err=io.StringIO()) == 0
    assert not (home / ".zshrc").exists()


def test_tui_menu_navigation_and_cli_merge_command(tmp_path: Path) -> None:
    items = build_menu_items()
    state = MenuState(items)
    assert state.current.key == "ansible"
    state.move(1)
    assert state.current.key == "check"
    state.move(-2)
    assert state.current.key == "quit"

    baseline = tmp_path / "base.json"
    target = tmp_path / "target.json"
    baseline.write_text(
        json.dumps({"permissions": {"deny": ["Read(~/.ssh/**)"]}}), encoding="utf-8"
    )
    rc = main(["merge-claude-settings", str(target), str(baseline)])
    assert rc == 0
    assert target.is_file()


def test_cli_forwards_ansible_and_check_flags(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    recorded: list[tuple[list[str], bool]] = []

    def fake_ansible(
        _paths: GroundhogPaths,
        extra_args: list[str],
        *,
        check: bool = False,
    ) -> int:
        recorded.append((extra_args, check))
        return 0

    monkeypatch.setattr("groundhog.cli.cmd_ansible", fake_ansible)
    paths = GroundhogPaths(repo_dir=tmp_path, home_dir=tmp_path)

    assert main(["ansible", "--tags", "dev-tools,agents,dotfiles", "-vv"], paths=paths) == 0
    assert main(["check", "--tags", "defaults"], paths=paths) == 0
    assert recorded == [
        (["--tags", "dev-tools,agents,dotfiles", "-vv"], False),
        (["--tags", "defaults"], True),
    ]


def test_cmd_ansible_skips_sudoers_staging_when_detached_sudo_works(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    calls: list[list[str]] = []

    class FakeProc:
        def __init__(self, returncode: int = 0) -> None:
            self.returncode = returncode

    def fake_run(cmd: list[str], **_kwargs: object) -> FakeProc:
        calls.append(cmd)
        return FakeProc(0)

    monkeypatch.setattr(
        "groundhog.ops.shutil.which",
        lambda _name: "/opt/homebrew/bin/ansible-playbook",
    )
    monkeypatch.setattr("groundhog.ops.subprocess.run", fake_run)

    paths = GroundhogPaths(repo_dir=tmp_path, home_dir=tmp_path)
    out = io.StringIO()
    rc = cmd_ansible(paths, ["--tags", "sudo"], check=True, out=out, err=io.StringIO())

    assert rc == 0
    assert calls == [
        ["sudo", "-n", "true"],
        ["ansible-playbook", str(paths.ansible_playbook), "--tags", "sudo", "--check", "--diff"],
    ]
    assert "non-interactive sudo" in out.getvalue()
