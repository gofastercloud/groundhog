# AGENTS.md — Groundhog Repository Guide

Groundhog manages a macOS developer workstation with Ansible, Homebrew, GNU Stow, a zero-dependency Python CLI + `curses` TUI (`./groundhog`), and a git-ignored private overlay (`custom/`). Follow these conventions whenever modifying configs, packages, or Ansible roles on the user's behalf.

## Core Architecture & Where Changes Belong

- **Public repo (`groundhog`)**: Generic, hardware-agnostic defaults only. **Never** commit usernames, `/Users/<name>` paths, emails, private hostnames/IPs, monitor model IDs, licence keys, or secrets here.
- **Private overlay (`custom/`, separate Git repo)**: Personal/hardware/cloud/AI/MAS packages (`custom/Brewfile`), feature flags and Dock layout (`custom/config.yml`), git identity (`custom/gitconfig`), personal symlinks (`custom/links.conf`), app-managed copies (`custom/copies.conf`), and private Ansible tasks (`custom/tasks.yml`).
- **Per-machine untracked overrides**: `ansible/vars/config.yml`, `homebrew/.Brewfile.local`, `~/.gitconfig.local`, `~/.ssh/config.local`, `~/.zshrc.local`. Runtime secrets management is intentionally out of scope for Groundhog.

### Decision Rule
- Useful to any macOS developer? Put it in **`groundhog`** (opt-in via a boolean in `ansible/vars/default.config.yml` if hardware-specific or opinionated).
- Personal, hardware-specific, paid/MAS, work/cloud account, or private network? Put it in **`custom/`**.

## Conventions & Hard-Won Guardrails

1. **Packages & Supply-Chain Cooldowns**:
   - Declare every formula, cask, font, and VS Code extension in `homebrew/.Brewfile` (core) or `custom/Brewfile` (personal). Keep `mas` entries out of the public `homebrew/.Brewfile`.
   - Maintain 7-day supply-chain cooldowns in `uv.toml.j2` (`exclude-newer = "7 days"`), `mise.toml.j2` (`minimum_release_age = "7d"`), and `npmrc.j2` (`min-release-age=7` + `ignore-scripts=true`).
2. **CLI (`src/groundhog/`) & Stow**:
   - `./groundhog` is a stdlib-only Python 3.11+ CLI & `curses` TUI (`./dotfiles.sh` is a thin compatibility shim). Keep zero external runtime dependencies in `src/groundhog/`.
   - `git`, `gh`, `vscode`, and `nushell` are stowed with `--no-folding` so runtime tokens, caches, and shell history never land inside the Git repository.
   - Directories containing untracked runtime state (`~/.ssh`, `~/.aws`, `~/.claude`, `~/.gemini`) use file-level symlinks via `manual_links()` or `custom/links.conf`.
   - Files rewritten atomically by apps go in `custom/copies.conf`; use `./groundhog capture` to pull live edits back.
3. **Ansible (`ansible/`)**:
   - Keep `ansible/roles/macos_defaults/tasks/main.yml` as an orchestrator that includes focused topic files (`animations.yml`, `dock_prefs.yml`, `performance.yml`, `finder.yml`, `keyboard.yml`, `privacy.yml`, `remote_login.yml`, `file_handlers.yml`, `shottr.yml`, `betterdisplay.yml`, `orbstack.yml`, `power.yml`).
   - Always use `set -euo pipefail` in shell tasks containing pipes (`risky-shell-pipe`).
   - Run Ansible via `./groundhog ansible [--tags "..."]`, `./groundhog check` (dry-run), or `make apply [TAGS="..."]` (uses `pipelining = True` and a temporary, `visudo`-validated global sudo ticket staged inside `/etc/sudoers.d/` and cleaned up on exit — never add `NOPASSWD: ALL`).
   - `/etc/pam.d/sudo_local` is rendered from a single template (`roles/sudo/templates/sudo_local.j2`) in fixed order (`pam_reattach` → `pam_immurok` → `pam_u2f` → `pam_tid`) and validated before and after via `roles/sudo/tasks/check_pam_modules.yml`. Never edit `/etc/pam.d/sudo` directly.
4. **SSH / SSHD & Secretive**:
   - Hardening lives in `/etc/ssh/sshd_config.d/050-hardening.conf` so it loads **before** macOS's `100-macos.conf` (`/etc/ssh/crypto.conf`) and preserves PQC-first `mlkem768x25519-sha256` KEX. Always validate with `/usr/sbin/sshd -t`.
   - Keep `ssh/.ssh/config` PQC-first (`mlkem768x25519-sha256`), AEAD-only ciphers, ETM-only MACs, `ForwardAgent no`, `HashKnownHosts yes`, and `IdentitiesOnly yes`.
5. **Shells (Nushell primary, Zsh login/fallback)**:
   - `zsh/.zprofile` owns `PATH`, Homebrew, `mise` shims, `JAVA_HOME`, `SSH_AUTH_SOCK`, and OrbStack for both Nushell and VS Code. Keep `zsh/.zshrc` minimal.
   - `mise activate nu` emits a Nushell *module* (`use`), not a `source`-able script — keep it at `$nu.data-dir/mise.nu`, never in `vendor/autoload/`.
   - When presenting interactive terminal commands to the user, use valid **Nushell** syntax (`rm -rfp`, `^open -a ...`, `$"..."`, no bash `$(...)`). Keep repo scripts POSIX/bash/zsh.
6. **macOS defaults quirks**:
   - Sandboxed apps (Shottr, Secretive) require Full Disk Access for the terminal running Ansible or inspecting their containers.
   - `duti` rejects dynamic (`dyn.*`) UTIs with error `-50` — bind only declared extensions.
7. **Autonomous GitHub workflow (`agent-git` & `agent-gh`)**:
   - When `agent_git_enabled` is configured, agents must use `agent-git` and `agent-gh` (see `skills/agent-git/SKILL.md`) instead of raw `git push` or human `gh` credentials.
   - Always work on `agent/<persona>/<slug>` branches, label PRs `agent-authored`, never push directly to `main`/`master`, and respect `repo_policies` (`human-review` repos must be left open with `needs-human-review` for human approval).

## Verification & Applying Changes

Verification is **local-first** (`pre-commit` + `pre-push` hooks, no hosted CI). Before finishing any edit in `groundhog`:
1. Update `tests/test_setup.sh` and `tests/test_groundhog.py` if you added/removed packages, feature flags, roles, CLI commands, or config invariants.
2. Run **`make verify`** (strict — fails on missing tools unless `ALLOW_SKIP=1`; runs Gitleaks, ShellCheck, `yamllint`, `ruff`, `ty`, `pytest`, `tests/test_setup.sh`, Nushell startup check, Ghostty/tmux/Neovim validation, Ansible syntax & lint, and `verify-custom`) — never weaken or skip tests to pass.
3. Confirm no personal data or `/Users/` paths leaked into `groundhog`.

Useful commands:
```bash
make doctor                                      # Check required verification tools
make hooks                                       # Install pre-commit + pre-push hooks
make verify                                      # Full strict lint + pytest + config test suite
./groundhog                                      # Interactive curses TUI
./groundhog status                               # Inspect stow, manual/custom links & overlay
./groundhog diff                                 # Diff repo against live $HOME
./groundhog link                                 # Reconcile symlinks, app copies & hooks
./groundhog check --tags "defaults"              # Dry-run Ansible (--check --diff)
./groundhog ansible --tags "defaults,dotfiles"   # Apply specific Ansible tags (single sudo auth)
./groundhog init-custom                          # Scaffold a new private overlay in custom/
./groundhog verify-custom                        # Validate custom/ manifests, YAML & SSH keys
```
