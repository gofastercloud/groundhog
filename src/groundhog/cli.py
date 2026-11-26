"""Non-interactive CLI and interactive TUI entry point for Groundhog."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from groundhog import __version__
from groundhog.agent_git import cmd_agent_git
from groundhog.config import GroundhogPaths
from groundhog.helpers import merge_claude_settings_file, tmux_copy_last
from groundhog.ops import (
    cmd_ansible,
    cmd_apply,
    cmd_brew,
    cmd_capture,
    cmd_diff,
    cmd_init_custom,
    cmd_link,
    cmd_status,
    cmd_unlink,
    cmd_verify_custom,
)
from groundhog.tui import run_tui


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="groundhog",
        description=(
            "Groundhog macOS workstation CLI. Run without a subcommand on an interactive "
            "terminal to launch the curses TUI, or pass a subcommand for non-interactive use."
        ),
    )
    parser.add_argument("--version", action="version", version=f"groundhog {__version__}")

    sub = parser.add_subparsers(dest="command")

    sub.add_parser("tui", help="Launch the interactive curses TUI")

    p_ansible = sub.add_parser(
        "ansible",
        help="Run Ansible playbook with single-auth sudo keepalive (forwards extra args)",
    )
    p_ansible.add_argument("ansible_args", nargs=argparse.REMAINDER)

    p_check = sub.add_parser(
        "check",
        help="Dry-run Ansible playbook with --check --diff (forwards extra args)",
    )
    p_check.add_argument("ansible_args", nargs=argparse.REMAINDER)

    sub.add_parser("apply", help="Install Brewfiles, stow configs, link custom overlay, and hooks")

    p_link = sub.add_parser("link", help="Stow configs, link manual/custom files, and hooks")
    p_link.add_argument("--skip-hooks", action="store_true", help="Skip pre-commit hook setup")
    p_link.add_argument("--skip-tmux", action="store_true", help="Skip TPM/tmux plugin install")
    p_link.add_argument("--skip-bat", action="store_true", help="Skip bat theme cache rebuild")

    sub.add_parser("unlink", help="Unstow all Stow-managed dotfile packages")
    sub.add_parser("status", help="Show link, custom overlay, and Homebrew status")
    sub.add_parser("diff", help="Diff repo configs against live files in $HOME")
    sub.add_parser("capture", help="Copy app-managed files (copies.conf) back into custom/")
    sub.add_parser("brew", help="Install Homebrew packages from core, custom, and local Brewfiles")
    sub.add_parser("init-custom", help="Scaffold a private overlay git repo in custom/")
    sub.add_parser("verify-custom", help="Validate custom/ YAML, manifests, SSH keys, and hooks")

    p_tmux = sub.add_parser(
        "tmux-copy-last",
        help="Capture active tmux pane's last command output to pbcopy",
    )
    p_tmux.add_argument("pane_id", help="tmux pane ID (e.g. %%0)")

    p_claude = sub.add_parser(
        "merge-claude-settings",
        help="Merge hardened baseline JSON into ~/.claude/settings.json",
    )
    p_claude.add_argument("target", type=Path, help="Target settings.json path")
    p_claude.add_argument("baseline", type=Path, help="Rendered baseline JSON fragment path")

    p_agent_git = sub.add_parser(
        "agent-git",
        help="Repo-scoped GitHub App broker and signing wrappers for autonomous agents",
    )
    p_agent_git.add_argument("agent_git_args", nargs=argparse.REMAINDER)

    return parser


def main(argv: list[str] | None = None, *, paths: GroundhogPaths | None = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    resolved = paths or GroundhogPaths.default()

    # Forward all flags verbatim to ansible-playbook / agent-git (argparse treats
    # leading `--tags` / `-v` as subparser flags even with REMAINDER).
    if raw_argv and raw_argv[0] in {"ansible", "check"}:
        extra = raw_argv[1:]
        if extra not in (["-h"], ["--help"]):
            return cmd_ansible(resolved, extra, check=(raw_argv[0] == "check"))
    if raw_argv and raw_argv[0] == "agent-git":
        return cmd_agent_git(resolved, raw_argv[1:])

    args = parser.parse_args(raw_argv)

    if args.command is None:
        if sys.stdin.isatty() and sys.stdout.isatty():
            return run_tui(resolved)
        parser.print_help()
        return 0

    if args.command == "tui":
        return run_tui(resolved)
    if args.command == "ansible":
        return cmd_ansible(resolved, args.ansible_args, check=False)
    if args.command == "check":
        return cmd_ansible(resolved, args.ansible_args, check=True)
    if args.command == "apply":
        return cmd_apply(resolved)
    if args.command == "link":
        return cmd_link(
            resolved,
            skip_hooks=args.skip_hooks,
            skip_tmux=args.skip_tmux,
            skip_bat=args.skip_bat,
        )
    if args.command == "unlink":
        return cmd_unlink(resolved)
    if args.command == "status":
        return cmd_status(resolved)
    if args.command == "diff":
        return cmd_diff(resolved)
    if args.command == "capture":
        return cmd_capture(resolved)
    if args.command == "brew":
        return cmd_brew(resolved)
    if args.command == "init-custom":
        return cmd_init_custom(resolved)
    if args.command == "verify-custom":
        return cmd_verify_custom(resolved)
    if args.command == "tmux-copy-last":
        return tmux_copy_last(args.pane_id)
    if args.command == "merge-claude-settings":
        changed = merge_claude_settings_file(args.target, args.baseline)
        if changed:
            print("CHANGED")
        return 0

    parser.print_help()
    return 1
