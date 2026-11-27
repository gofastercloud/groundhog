---
name: groundhog
description: >-
  Manage a macOS workstation configured with Groundhog (Ansible, Homebrew,
  GNU Stow, Nushell, PQC SSH, and a git-ignored custom/ private overlay).
  Use whenever the user asks to install or remove a Mac app, CLI, cask, font,
  or VS Code extension; change a macOS default, Dock item, or desktop app
  setting; edit dotfiles (Nushell, Zsh, Ghostty, tmux, Neovim, Git, SSH,
  VS Code); toggle an optional Groundhog role; or verify/apply workstation
  changes.
---

# Groundhog Workstation Management Skill

Use this skill whenever you are asked to install software, change macOS settings, edit dotfiles, or apply configuration changes on a Groundhog-managed Mac. **Never run ad-hoc `brew install` or scatter manual edits in `$HOME`** when a declarative Groundhog file owns that state.

## 1. Decide Where the Change Belongs

Groundhog splits state cleanly across three layers:

| Layer | Path | Put it here when… |
|---|---|---|
| **Public Core (`groundhog`)** | Repo root (`homebrew/.Brewfile`, `ansible/`, stow packages) | Useful to *any* macOS developer, hardware-agnostic, free of usernames (`/Users/<name>`), emails, private hosts, paid/MAS apps, or secrets. Opt-in opinionated features go behind a boolean defaulted to `false` in `ansible/vars/default.config.yml`. |
| **Private Overlay (`custom/`)** | `custom/` (separate git-ignored repo) | Personal/work apps, paid or Mac App Store (`mas`) apps, cloud/AI CLIs, Dock layout (`custom/config.yml`), feature flags, Git identity (`custom/gitconfig`), homelab SSH hosts (`custom/links.conf`), app-managed copies (`custom/copies.conf`), or private Ansible tasks (`custom/tasks.yml`). |
| **Machine-Local (Untracked)** | `ansible/vars/config.yml`, `homebrew/.Brewfile.local`, `~/.gitconfig.local`, `~/.ssh/config.local`, `~/.zshrc.local` | One-off overrides strictly for the current Mac. |

**Rule of thumb:** If unsure whether an app is universal or personal, put it in `custom/Brewfile` (if `custom/` exists) — keeping public `groundhog` lean is always safer.

## 2. Common Workflows

### A. Install a new CLI, desktop app (cask), font, or VS Code extension
1. Check whether the tool is already declared in `homebrew/.Brewfile` or `custom/Brewfile`.
2. Add the declaration in alphabetical order under the matching section comment:
   - CLI formula: `brew "watchexec"  # Short description`
   - GUI app: `cask "linear-linear"  # Short description`
   - VS Code extension: `vscode "publisher.extension"`
   - Mac App Store app (**`custom/Brewfile` only**, never public): `mas "App Name", id: 123456789`
3. If the user also wants the app pinned to the Dock, append `/Applications/<App>.app` to `dock_apps` in `custom/config.yml`.
4. Preview and apply with tags (fast, single-auth):
   ```bash
   ./groundhog check --tags "homebrew,dock"
   ./groundhog ansible --tags "homebrew,dock"
   ```
5. If you added a core package to public `homebrew/.Brewfile`, add an assertion in `tests/test_setup.sh` if it is a core invariant.

### B. Edit dotfiles or add a new Stow package
- Edit tracked files inside the repo (`zsh/`, `nushell/`, `ghostty/`, `tmux/`, `nvim/`, `git/`, `vscode/`, etc.), never directly in `$HOME` if unlinked.
- Stateful directories (`git`, `gh`, `vscode`, `nushell`) **must** stay in `NO_FOLDING_PACKAGES` (`src/groundhog/config.py`) so caches, tokens, and shell history never land in Git.
- Directories with untracked runtime state (`~/.ssh`, `~/.aws`, `~/.claude`, `~/.gemini`) use file-level symlinks via `manual_links()` or `custom/links.conf`.
- Files rewritten atomically by apps (which break symlinks) belong in `custom/copies.conf`. Pull live app edits back with `./groundhog capture`.
- Reconcile symlinks and hooks with `./groundhog link` and inspect with `./groundhog status` or `./groundhog diff`.

### C. Add a macOS default or desktop app preference
- Place macOS defaults in the appropriate topic file under `ansible/roles/macos_defaults/tasks/` (`animations.yml`, `dock_prefs.yml`, `performance.yml`, `finder.yml`, `keyboard.yml`, `privacy.yml`, `remote_login.yml`, `file_handlers.yml`, `shottr.yml`, `betterdisplay.yml`, `orbstack.yml`, `power.yml`). Keep `main.yml` as a clean include orchestrator.
- Guard optional apps with `ansible.builtin.stat` or `command -v` so tasks degrade cleanly on fresh machines.
- Preview with `./groundhog check --tags defaults` before applying with `./groundhog ansible --tags defaults`.

### D. Enable an optional Groundhog feature flag
Set the flag in `custom/config.yml` (or `ansible/vars/config.yml`):
- `claude_code_enabled: true` — Seatbelt sandbox + widened deny rules + `ruff` hook + Groundhog skill link
- `antigravity_enabled: true` — templated `trustedWorkspaces` + Groundhog skill link
- `codex_enabled: true` — hardened `~/.codex/config.toml` scaffold (`workspace-write`, no network, `core` env policy) + Groundhog skill link
- `agent_git_enabled: true` — 1-hour single-repo `agent-git`/`agent-gh` GitHub App broker & signing-only SSH key
- `agency_enabled: true` — vendor-agnostic `groundhog-agency` skills (`/spec`, `/next`, `/handoff`) & `agency-{install,dash,report}` wrappers
- `remote_login_enabled: true` — hardened `sshd` (`050-hardening.conf`, ML-KEM-768 PQC) + Mosh
- `yubikey_enabled: true` — FIDO2 `pam_u2f` sudo auth
- `immurok_enabled: true` — immurok fingerprint key sudo auth

### Adopting Groundhog on an Existing Mac (Agent-Guided)
When a user already has a configured Mac and wants to adopt Groundhog safely without breaking their setup:
1. Run `./groundhog adopt --json` (read-only audit) and walk the user through every conflicting dotfile, extra Homebrew/VS Code entry, current Dock layout, and any secret warnings.
2. Run `./groundhog adopt --apply` to snapshot all conflicting originals into `~/.backups/groundhog-adopt-<ts>/` (with `manifest.json`) and seed `custom/` + `*.local`.
3. Semantically clean up the adopted files with the user: trim one-off/transitive packages from `custom/Brewfile`, merge shell aliases into `~/.zshrc.local` (stripping any hardcoded secrets into a secrets manager), and verify `custom/config.yml`.
4. Roll out incrementally — always dry-run first (`./groundhog check --tags "<tag>"`) before applying (`dotfiles` → `dev-tools` → `homebrew` → `defaults` → `dock`).
5. Remind the user they can roll back cleanly at any time via `./groundhog clean --restore`.

## 3. Non-Negotiable Guardrails

- **Zero personal leaks in public `groundhog`**: Never commit `/Users/<name>`, emails, private hostnames/IPs, licence keys, or secrets.
- **No bundled secrets management**: Never store API tokens or `.env` files in either repo; instruct the user to keep secrets in their own secrets manager (`op run`, macOS Keychain, `sops`, etc.).
- **Preserve supply-chain cooldowns**: Keep the 7-day cooldowns in `uv.toml.j2` (`exclude-newer = "7 days"`), `mise.toml.j2` (`minimum_release_age = "7d"`), and `npmrc.j2` (`min-release-age=7` + `ignore-scripts=true`), and keep pinned SHAs for tmux plugins, Homebrew's installer, and Ansible Galaxy.
- **Never edit `/etc/pam.d/sudo` or add `NOPASSWD: ALL`**: PAM edits go only through `roles/sudo/templates/sudo_local.j2` validated by `check_pam_modules.yml`.
- **Keep `src/groundhog/` zero-dependency**: Runtime CLI and `curses` TUI code uses Python stdlib only.

## 4. Verification Before Finishing

Always run strict local verification before reporting done (never pass `--no-verify` or weaken tests):

```bash
make verify                 # pre-commit, ruff, ty, pytest, test_setup.sh, nu check, ansible-lint, verify-custom
./groundhog verify-custom   # Validate custom/ YAML, manifests, SSH keys & git hooks
```
