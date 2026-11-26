"""Unit-tested helper utilities extracted from inline tmux/Ansible Python scripts."""

from __future__ import annotations

import copy
import json
import re
import subprocess
from pathlib import Path
from typing import Any

# Matches oh-my-posh's U+F105 prompt closer or a standard POSIX user@host prompt.
PROMPT_RE = re.compile(chr(0xF105) + r"([ \t]|$)|^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:.*[%#$]([ \t]|$)")


def extract_last_command_output(lines: list[str]) -> str:
    """Return the output block between the second-to-last and last shell prompt."""
    idxs = [idx for idx, line in enumerate(lines) if PROMPT_RE.search(line)]
    if len(idxs) < 2:
        return ""
    start = idxs[-2] + 1
    end = idxs[-1]
    if start >= end:
        return ""
    return "\n".join(lines[start:end]).rstrip()


def tmux_copy_last(pane_id: str) -> int:
    """Capture the active tmux pane's last command output and copy it to pbcopy."""
    captured = subprocess.check_output(
        ["tmux", "capture-pane", "-t", pane_id, "-p", "-J", "-S", "-"],
        text=True,
    )
    output = extract_last_command_output(captured.splitlines())
    subprocess.run(["pbcopy"], input=output, text=True, check=True)
    line_count = len(output.splitlines()) if output else 0
    subprocess.run(
        ["tmux", "display-message", f"Copied {line_count} line(s) from last command"],
        check=False,
    )
    return 0


def merge_claude_settings(
    current: dict[str, Any],
    baseline: dict[str, Any],
) -> tuple[dict[str, Any], bool]:
    """Merge hardened Claude Code baseline settings without clobbering user prefs."""
    merged: dict[str, Any] = copy.deepcopy(current)
    before = json.dumps(current, sort_keys=True)

    # Enforce OS-level sandboxing
    sandbox = merged.setdefault("sandbox", {})
    if not isinstance(sandbox, dict):
        sandbox = {}
        merged["sandbox"] = sandbox
    sandbox["enabled"] = True
    sandbox["allowUnsandboxedCommands"] = False

    # Merge deny rules while preserving extra user rules
    perms = merged.setdefault("permissions", {})
    if not isinstance(perms, dict):
        perms = {}
        merged["permissions"] = perms
    existing_deny = perms.get("deny", [])
    merged_deny: list[str] = list(existing_deny) if isinstance(existing_deny, list) else []
    baseline_deny = baseline.get("permissions", {}).get("deny", [])
    for rule in baseline_deny:
        if rule not in merged_deny:
            merged_deny.append(rule)
    perms["deny"] = sorted(set(merged_deny))

    # Seed PostToolUse ruff hook if the user has not defined any PostToolUse hooks
    hooks = merged.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        hooks = {}
        merged["hooks"] = hooks
    baseline_post = baseline.get("hooks", {}).get("PostToolUse")
    if baseline_post and not hooks.get("PostToolUse"):
        hooks["PostToolUse"] = copy.deepcopy(baseline_post)

    after = json.dumps(merged, sort_keys=True)
    return merged, before != after


def merge_claude_settings_file(target: Path, baseline_path: Path) -> bool:
    """Merge baseline JSON into target settings file on disk. Returns True if written."""
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    existed = target.exists()
    current = json.loads(target.read_text(encoding="utf-8")) if existed else {}
    merged, changed = merge_claude_settings(current, baseline)
    if changed or not existed:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
        target.chmod(0o600)
        return True
    return False
