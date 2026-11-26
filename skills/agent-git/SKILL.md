---
name: agent-git
description: >-
  Commit, push, open pull requests, and manage GitHub interactions as an
  autonomous agent using Groundhog's repo-scoped GitHub App broker
  (`agent-git` and `agent-gh`). Use whenever an agent needs to commit, push a
  branch, create or merge a pull request, or interact with GitHub without
  touching the user's hardware-bound Secretive master keys.
---

# Agent GitHub Workflow (`agent-git` & `agent-gh`)

Use `agent-git` and `agent-gh` for **all** autonomous Git commits, pushes, and GitHub API interactions. Never use raw `git push` or `gh` with the user's personal Secretive/OAuth credentials when acting autonomously.

## How It Works
- **Commit signing**: `agent-git` signs every commit with the dedicated, revocable signing-only SSH key (`~/.ssh/id_agent_mbp_sign.pub`) under the zero-privilege bot committer identity, producing `Verified` commits on every branch without touching Secretive.
- **Repo-scoped auth**: `agent-git` and `agent-gh` mint a **1-hour, single-repository** GitHub App installation token on demand from macOS Keychain.
- **Human workflow untouched**: The repo's `.git/config` and global `~/.gitconfig` are never modified.

## Standard Workflow

1. **Create an `agent/*` branch** (never commit or push directly to `main` or `master`):
   ```bash
   agent-git checkout -b agent/<persona>/<short-slug>
   ```
   Optionally set `AGENT_NAME="Codex Agent"` (or your agent persona name) so `GIT_AUTHOR_NAME` clearly identifies which agent authored the change.

2. **Commit cleanly** (signed automatically):
   ```bash
   agent-git add <files>
   agent-git commit -m "Clear imperative summary"
   ```

3. **Push the feature branch** (automatically uses the 1-hour single-repo App token over HTTPS):
   ```bash
   agent-git push -u origin agent/<persona>/<short-slug>
   ```

4. **Open a Pull Request with attribution labels**:
   Check `groundhog agent-git status` (or `~/.config/groundhog/agent-git.json` → `repo_policies`) to see whether the repo is `autonomous` (default) or `human-review`:
   - **Autonomous repos**:
     ```bash
     agent-gh pr create --fill --label agent-authored
     ```
     Wait for checks to pass, then squash-merge and delete the branch:
     ```bash
     agent-gh pr merge --squash --delete-branch
     ```
   - **Human-gated repos (`human-review`)**:
     ```bash
     agent-gh pr create --fill --label agent-authored --label needs-human-review
     ```
     **Stop here.** Do not attempt to merge — both `agent-gh` locally and GitHub's Branch Ruleset server-side block merges until the user reviews and approves.

## Guardrails
- Never push directly to `main` or `master`.
- Never bypass pre-commit / Gitleaks hooks (`--no-verify` is forbidden).
- Never ask the user to unlock Secretive for routine agent pushes.
- Run `groundhog agent-git status` to verify the signing key, Keychain App key, and repo policies before troubleshooting auth errors.
