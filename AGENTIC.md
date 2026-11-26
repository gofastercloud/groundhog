# Getting Started with Groundhog for Agentic Development

Coding agents are genuinely fun to work with when they have room to run, and genuinely nerve-racking when they share your raw host environment with your SSH keys, cloud tokens, and production repos.

Groundhog gives you a calm, practical baseline for running agents like Claude Code, Google Antigravity, Codex, or OpenCode on macOS without either living in fear or crippling your daily flow.

## 1. Enable the opt-in agent baselines

In your `custom/config.yml` (or per-machine `ansible/vars/config.yml`), flip on the agents you actually use:

```yaml
claude_code_enabled: true
antigravity_enabled: true

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
./dotfiles.sh ansible --tags "homebrew,agents,dev-tools"
```

What those roles configure for you:
- **Claude Code** (`roles/claude_code`): merges OS-level Seatbelt sandboxing (`sandbox.enabled: true`, `allowUnsandboxedCommands: false`), a secret-path deny list (`~/.ssh/**`, `~/.aws/**`, `~/.config/gh/**`, `~/.config/private/**`, `.env*`, `*.pem`, `*.key`, `git push --force`), and an automatic `ruff` formatter hook into `~/.claude/settings.json` without overwriting your existing plugins, theme, or model settings.
- **Antigravity CLI** (`roles/antigravity`): writes `~/.gemini/antigravity-cli/settings.json` with templated `trustedWorkspaces` (no hardcoded home-directory paths).

## 2. Defence in depth (why deny lists alone are not enough)

Agent deny lists are helpful guardrails, not hard OS boundaries. A prompt-injected shell command can still invoke Python or Node to read whatever your user account can read. Groundhog layers four real boundaries underneath the agent:

| Layer | What Groundhog enforces | Why it matters |
|-------|-------------------------|----------------|
| **Hardware-bound SSH** | [Secretive](https://github.com/maxgoedjen/secretive) Secure Enclave keys + `ForwardAgent no` | There is no `~/.ssh/id_ed25519` file on disk for an agent to exfiltrate. |
| **Scoped secrets** | `~/.config/private/secrets.env` (`0600`) + `with-secrets` + `age` | Tokens stay out of your default shell environment and out of agent context windows. |
| **Supply-chain locks** | `npmrc` `ignore-scripts=true`, `uv` + venv-only `pip`, `git` `fsckObjects=true`, `gitleaks`, `trufflehog`, `osv-scanner` | Stops malicious `postinstall` hooks and accidental secret commits when agents install dependencies. |
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

## 4. Isolate untrusted repos with `agent-box`

When you want to poke at an unfamiliar repository, test an autonomous loop, or run untrusted install scripts, drop into `agent-box` (`autoload/orb.nu`). It launches a disposable OrbStack container (`--rm`) with:
- **Only** your current working directory mounted at `/workspace` (zero `~/.ssh`, `~/.aws`, `~/.config/private`, or host `$HOME` visibility)
- `--cap-drop=ALL` and `--security-opt=no-new-privileges:true`
- **Network disabled by default** (`--network=none`; pass `--net` only when outbound access is actually required)

```nu
# Offline disposable sandbox on the current directory
agent-box

# Same, with outbound network and a Python image
agent-box --net --image python:3.14-slim
```

## 5. Secrets & MCP hygiene

- **Never put live secrets in `.env` files inside agent workspaces.** Use `with-secrets <cmd>` for local commands, or encrypt at rest with `age` / `sops`. If you already use 1Password, `op run` / 1Password Environments pairs cleanly with this setup.
- **Prefer local CLIs over stacking MCP servers.** Tools like `gh`, `uv`, `ruff`, `ast-grep`, `jq`, `yq`, and `difftastic` burn far fewer context tokens than bloated MCP schemas and avoid running unpinned `npx -y` servers.
- **Keep `AGENTS.md` in your repos.** Both `groundhog` and `custom.example/` include an `AGENTS.md` (with a `CLAUDE.md` `@AGENTS.md` pointer) so any agent knows your guardrails before touching a line of config.
