# Getting Started with Groundhog for Agentic Development

Coding agents are genuinely fun to work with when they have room to run, and genuinely nerve-racking when they share your raw host environment with your SSH keys, cloud tokens, and production repos.

Groundhog gives you a calm, practical baseline for running agents like Claude Code, Google Antigravity, Codex, or OpenCode on macOS without either living in fear or crippling your daily flow.

## 1. Enable the opt-in agent baselines

In your `custom/config.yml` (or per-machine `ansible/vars/config.yml`), flip on the agents you actually use:

```yaml
claude_code_enabled: true
antigravity_enabled: true
codex_enabled: true
agent_git_enabled: true
agency_enabled: true
agency_repo_dir: "{{ home_dir }}/Code/projects/groundhog-agency"

# Optional: block extra private directories in Claude Code
claude_code_extra_deny:
  - "Read(~/.work-secrets/**)"

# Optional: customise Antigravity CLI trusted workspaces
antigravity_trusted_workspaces:
  - "{{ home_dir }}/Code"
```

Add the matching casks to `custom/Brewfile` (for example `cask "claude-code@latest"`, `cask "antigravity"`, `cask "antigravity-cli"`), then apply:

```nu
cd ~/groundhog
./groundhog ansible --tags "homebrew,agents,dev-tools"
```

What those roles configure for you:
- **Claude Code** (`roles/claude_code`): merges OS-level Seatbelt sandboxing (`sandbox.enabled: true`, `allowUnsandboxedCommands: false`), widened secret-path `Read`/`Edit`/`Write` deny rules (`~/.ssh/**`, `~/.aws/**`, `~/.config/gh/**`, `~/.gnupg/**`, `~/.config/private/**`, `.env*`, `*.pem`, `*.key`), destructive push blocks (`git push --force`, `--force-with-lease`, `+*`, `--delete`), and an automatic `ruff` formatter hook into `~/.claude/settings.json` without overwriting your existing plugins, theme, or model settings.
- **Antigravity CLI** (`roles/antigravity`): writes `~/.gemini/antigravity-cli/settings.json` with templated `trustedWorkspaces` (no hardcoded home-directory paths).
- **Codex CLI** (`roles/codex`): scaffolds `~/.codex/config.toml` (`force: false`) with `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, `network_access = false`, and `shell_environment_policy` (`inherit = "core"`).
- **Agent GitHub broker** (`roles/agent_git`): templates `~/.config/groundhog/agent-git.json`, installs `~/.local/bin/agent-git` and `~/.local/bin/agent-gh` (1-hour single-repo GitHub App tokens + dedicated signing-only SSH key, keeping your Secretive master keys untouched), and links `skills/agent-git` into Claude, Antigravity, and Codex.

## 2. Defence in depth (why deny lists alone are not enough)

Agent deny lists are helpful guardrails, not hard OS boundaries. A prompt-injected shell command can still invoke Python or Node to read whatever your user account can read. Groundhog layers four real boundaries underneath the agent:

| Layer | What Groundhog enforces | Why it matters |
|-------|-------------------------|----------------|
| **Hardware-bound SSH** | [Secretive](https://github.com/maxgoedjen/secretive) Secure Enclave keys + `ForwardAgent no` | There is no `~/.ssh/id_ed25519` file on disk for an agent to exfiltrate. |
| **Supply-chain cooldowns** | 7-day release delays in `uv` (`exclude-newer`), `mise` (`minimum_release_age`), and `npm` (`min-release-age`) + `npm` `ignore-scripts=true` + venv-only `pip` | Blocks freshly published supply-chain malware (TeamPCP-style attacks) and malicious `postinstall` hooks when agents install dependencies. |
| **Git & secret hygiene** | Global Git `init.templateDir` Gitleaks hook, `pre-commit` + `pre-push` Gitleaks range scanning, `git` `fsckObjects=true`, `trufflehog`, `osv-scanner` | Every brand-new repo gets staged-secret protection automatically, and `--no-verify` commits are caught before push. |
| **Container & host walls** | OrbStack LAN/SSH exposure off, macOS Firewall + Stealth Mode, 60s `sudo` cache (no `NOPASSWD`), `agent-box` | Keeps local services off the LAN and gives you a zero-credential sandbox on demand. |

## 3. Run parallel agents cleanly with `gwt` + `sesh`

Running two agents in the same checkout is the fastest way to corrupt lockfiles and fight over uncommitted edits. Groundhog ships a `gwt` helper in Nushell (`autoload/git.nu`) wired to `sesh` and `tmux`:

```nu
# Spin up a sibling worktree on a new branch and jump straight into its tmux session
gwt add feat/auth-refresh --sesh

# List active worktrees as a structured Nushell table
gwt

# Jump back into an existing worktree session
gwt open feat/auth-refresh

# Clean up once the PR is merged
gwt rm feat/auth-refresh
```

If a repo has a `.worktreeinclude` file (one relative path per line, such as local non-secret config files), `gwt add` copies those into the fresh worktree automatically.

## 4. Isolate untrusted repos and test runs with `agent-box`

When you want to poke at an unfamiliar repository, test an autonomous loop, or run untrusted install/test scripts, use `agent-box` (`~/.local/bin/agent-box` / `autoload/orb.nu`). It auto-starts OrbStack if stopped, auto-builds Groundhog's lightweight non-root `groundhog-agent-box:latest` image (Python 3.13, `uv` with 7-day cooldown, `ruff`, `pytest`, `git`, `ripgrep`, `make`), and launches a disposable container (`--rm`) with:
- **Only** your target directory mounted at `/workspace` (zero `~/.ssh`, `~/.aws`, `~/.config/groundhog`, or host `$HOME` visibility)
- `--read-only` root filesystem, `--cap-drop=ALL`, `--security-opt=no-new-privileges:true`, `--pids-limit 256`
- **Network disabled by default** (`--network=none`; pass `--net` only when outbound access is actually required)

```nu
# Offline interactive sandbox on the current directory
agent-box

# Run tests/verify offline in a worktree (default in groundhog-agency)
agent-box -- make verify
agent-box --dir ../wt -- uv run pytest -q

# Rebuild the local groundhog-agent-box image
agent-box --build

# Custom image with outbound network
agent-box --net --image python:3.13-slim
```

## 5. Vendor-agnostic autonomous agency (`groundhog-agency`)

Enable `agency_enabled: true` and `agent_git_enabled: true` to link the canonical `/spec`, `/next`, and `/handoff` skills into Claude Code, Antigravity, and Codex and install `agency-install`, `agency-dash`, and `agency-report`:

```nu
# One-command repo onboarding (files, CODEOWNERS, labels, signed-commit ruleset, setup PR)
agency-install /path/to/repo --ship

# Launch orchestrator + live tmux dashboard
agency-dash up --vendor claude   # or --vendor codex
```

Implementers and reviewers run verification inside offline `agent-box` by default, sign commits via `agent-git` (dedicated signing-only key in `~/.config/groundhog/`), and ship PRs via `agent-gh` respecting each repo's `autonomous` vs `human-review` policy.

## 5. Autonomous GitHub workflow (`agent-git` & `agent-gh`)

When `agent_git_enabled` is on, agents sign commits with a dedicated, revocable signing-only SSH key and push/PR via **1-hour, single-repository** GitHub App tokens — leaving your Secretive master keys untouched:

```nu
agent-git checkout -b agent/codex/fix-parser
agent-git add ...
AGENT_NAME="Codex Agent" agent-git commit -m "Fix edge case in parser"
agent-git push -u origin agent/codex/fix-parser
agent-gh pr create --fill --label agent-authored
```

- Direct pushes to `main`/`master` and non-`agent/*` branches are blocked locally and enforced server-side via GitHub Branch Rulesets.
- Repos listed as `human-review` in `agent_git_repo_policies` block `agent-gh pr merge` locally (in addition to GitHub requiring human PR approval); autonomous repos can squash-merge once checks pass.
- Run `./groundhog agent-git status` to inspect App ID, signing key, Keychain status, and repo policies.

## 6. Secrets & MCP hygiene

- **Organise secrets outside Groundhog.** Groundhog deliberately avoids keeping a plaintext secrets file on disk. Use your preferred secrets manager (such as 1Password CLI `op run`, macOS Keychain, or `sops`/`age`) to inject credentials per command rather than exporting them globally or dropping live `.env` files inside agent workspaces.
- **Prefer local CLIs over stacking MCP servers.** Tools like `gh`, `uv`, `ruff`, `ast-grep`, `jq`, `yq`, and `difftastic` burn far fewer context tokens than bloated MCP schemas and avoid running unpinned `npx -y` servers.
- **Keep `AGENTS.md` and `skills/groundhog/SKILL.md` wired up.** Both `groundhog` and `custom.example/` include `AGENTS.md` (with a `CLAUDE.md` `@AGENTS.md` pointer), and `skills/groundhog/SKILL.md` teaches any coding agent how to install apps, edit dotfiles, and verify changes declaratively. When `claude_code_enabled` or `antigravity_enabled` is on, Groundhog symlinks `skills/groundhog` straight into `~/.claude/skills/groundhog` and `~/.gemini/antigravity/skills/groundhog`.
