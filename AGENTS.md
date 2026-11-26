# AGENTS.md — Groundhog Repository Guide

Groundhog manages a macOS developer workstation with Ansible, Homebrew, GNU Stow, and a git-ignored private overlay (`custom/`). Follow these conventions whenever modifying configs, packages, or Ansible roles on the user's behalf.

## Core Architecture & Where Changes Belong

- **Public repo (`groundhog`)**: Generic, hardware-agnostic defaults only. **Never** commit usernames, `/Users/<name>` paths, emails, private hostnames/IPs, monitor model IDs, licence keys, or secrets here.
- **Private overlay (`custom/`, separate Git repo)**: Personal/hardware/cloud/AI/MAS packages (`custom/Brewfile`), feature flags and Dock layout (`custom/config.yml`), git identity (`custom/gitconfig`), personal symlinks (`custom/links.conf`), app-managed copies (`custom/copies.conf`), and private Ansible tasks (`custom/tasks.yml`).
- **Per-machine untracked overrides**: `ansible/vars/config.yml`, `homebrew/.Brewfile.local`, `~/.gitconfig.local`, `~/.ssh/config.local`, `~/.zshrc.local`, `~/.config/private/secrets.env` (`chmod 600`).

### Decision Rule
- Useful to any macOS developer? Put it in **`groundhog`** (opt-in via a boolean in `ansible/vars/default.config.yml` if hardware-specific or opinionated).
- Personal, hardware-specific, paid/MAS, work/cloud account, or private network? Put it in **`custom/`**.

## Conventions & Hard-Won Guardrails

1. **Packages**: Declare every formula, cask, font, and VS Code extension in `homebrew/.Brewfile` (core) or `custom/Brewfile` (personal). Do not run ad-hoc `brew install` without adding the entry to the appropriate Brewfile. Keep `mas` entries out of the public `homebrew/.Brewfile`.
2. **Stow & stateful directories**:
   - `gh`, `vscode`, and `nushell` are stowed with `--no-folding` so runtime tokens, caches, and shell history never land inside the Git repository.
   - Directories containing untracked runtime state (`~/.ssh`, `~/.aws`, `~/.claude`, `~/.gemini`) use file-level symlinks via `MANUAL_LINKS` or `custom/links.conf`.
   - Files rewritten atomically by apps (which break symlinks) go in `custom/copies.conf`; use `./dotfiles.sh capture` to pull live edits back.
3. **Ansible (`ansible/`)**:
   - Keep `ansible/roles/macos_defaults/tasks/main.yml` below `ansible-lint`'s 100-task complexity limit by placing app-specific defaults in dedicated `tasks/<app>.yml` files included from `main.yml`.
   - Always use `set -euo pipefail` in shell tasks containing pipes (`risky-shell-pipe`).
   - Run Ansible via `./dotfiles.sh ansible [--tags "..."]` or `make apply [TAGS="..."]` (uses `pipelining = True` and a temporary, `visudo`-validated global sudo ticket cleaned up on exit — never add `NOPASSWD: ALL`).
   - `/etc/pam.d/sudo_local` is rendered from a single template (`roles/sudo/templates/sudo_local.j2`) in fixed order (`pam_reattach` → `pam_immurok` → `pam_u2f` → `pam_tid`) and validated before writing. Never edit `/etc/pam.d/sudo` directly.
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

## Verification & Applying Changes

Before finishing any edit in `groundhog`:
1. Update `tests/test_setup.sh` if you added/removed packages, feature flags, roles, or config invariants.
2. Run **`make verify`** (Gitleaks, ShellCheck, `ansible-lint` production profile, `yamllint`, Nushell startup check, Ghostty/tmux/Neovim validation, Ansible syntax check, and `tests/test_setup.sh`) — never weaken or skip tests to pass.
3. Confirm no personal data or `/Users/` paths leaked into `groundhog`.

Useful commands:
```bash
make verify                                      # Full lint + config test suite
./dotfiles.sh status                             # Inspect stow, manual/custom links & overlay
./dotfiles.sh diff                               # Diff repo against live $HOME
./dotfiles.sh link                               # Reconcile symlinks & app copies
./dotfiles.sh ansible --tags "defaults,dotfiles" # Apply specific Ansible tags (single sudo auth)
./dotfiles.sh init-custom                        # Scaffold a new private overlay in custom/
```
