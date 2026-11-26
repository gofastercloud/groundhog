# Groundhog

Rebuild your exact macOS developer workstation identically every time — using [Ansible](https://docs.ansible.com/), [Homebrew](https://brew.sh/), [GNU Stow](https://www.gnu.org/software/stow/), and a clean **private overlay** (`custom/`) so personal packages, SSH hosts, and cloud configs stay in your own private repository with zero merge conflicts.

Includes a Nushell-first terminal stack (Ghostty + tmux + sesh + Neovim + Catppuccin Mocha), `mise`/`uv` runtime management, PQC-first SSH/SSHD (`mlkem768x25519-sha256`) with [Secretive](https://github.com/maxgoedjen/secretive) Secure Enclave keys, macOS defaults, VS Code settings & extensions, OrbStack hardening, and portable Shottr & BetterDisplay preferences.

## Quick Start

### 1. Clone Groundhog

```bash
git clone https://github.com/YOUR_USERNAME/groundhog.git ~/groundhog
cd ~/groundhog
```

### 2. (Optional) Create or Attach Your Private Overlay (`custom/`)

Groundhog works out of the box with clean, hardware-agnostic defaults (no Mac App Store sign-in required, no YubiKey/immurok/inbound SSH enabled by default).

To keep your own personal packages, Dock layout, SSH hosts, AWS/AI configs, and feature flags in a **separate private Git repository** (`groundhog-private`):

- **New user** — scaffold a ready-to-push private overlay repo in one command:
  ```bash
  ./dotfiles.sh init-custom
  # Edit custom/config.yml, custom/Brewfile, custom/gitconfig, custom/links.conf
  cd custom && git add -A && git commit -m "Initial private overlay"
  gh repo create groundhog-private --private --source=. --push
  ```
- **Returning user on a fresh Mac** — clone your private overlay directly into `custom/`:
  ```bash
  git clone git@github.com:YOUR_USERNAME/groundhog-private.git ~/groundhog/custom
  ```

Because `custom/` is git-ignored by `groundhog`, you can `git pull` upstream updates cleanly forever with zero rebase or merge conflicts.

### 3. Bootstrap a Fresh Mac

Before running `bootstrap.sh`:
1. **Grant Full Disk Access to `Terminal.app`**: *System Settings → Privacy & Security → Full Disk Access → enable Terminal*. Without this, macOS silently blocks or fails Remote Login (`systemsetup`), Reduce Transparency/Motion, and sandboxed app defaults (Shottr).
2. **Sign in to the Mac App Store** *only* if your `custom/Brewfile` includes `mas` entries.

Run the bootstrap script:

```bash
bash ansible/bootstrap.sh
```

Re-run specific roles later with tags:

```bash
ansible-playbook ansible/setup.yml --ask-become-pass --tags "homebrew,defaults,dotfiles"
```

### Dotfiles Only (Without Full Ansible Run)

```bash
brew install stow
./dotfiles.sh apply    # brew install + stow + manual/custom links + tmux plugins
# or link only:
./dotfiles.sh link
```

## Manual Post-Bootstrap Steps

macOS privacy boundaries (TCC/SIP), hardware-bound keys, and cloud accounts cannot be scripted safely. After `bootstrap.sh` finishes:

1. **Log out and log back in** (or reboot) so keyboard repeat, menu bar, Finder, and Dock defaults take full effect.
2. **macOS System Settings (TCC & security)**:
   - *Privacy & Security → Full Disk Access*: allow **Ghostty** (for future Ansible runs).
   - *Privacy & Security → Screen & System Audio Recording*: allow **Shottr**.
   - *Privacy & Security → Accessibility*: allow **Raycast** and **BetterDisplay**.
   - *Privacy & Security → FileVault*: confirm disk encryption is enabled.
   - *Lock Screen* & *Focus*: configure idle lock timing and Focus modes.
   - *General → Login Items & Extensions → Network Extensions*: approve **Tailscale** (and any egress firewall in your `custom/Brewfile`).
3. **Secretive (Secure Enclave SSH & git signing)**: Open Secretive, enable SecretAgent, create authentication and signing keys, symlink `~/.ssh/id_secretive.pub` and `~/.ssh/id_secretive_sign.pub`, set `user.name`/`user.email` in `custom/gitconfig` (or `~/.gitconfig.local`), and register the public keys on GitHub and your servers (see [Secretive Setup](#secretive-secure-enclave-ssh)).
4. **OrbStack**: Launch `OrbStack.app` once to finish initialising the CLI and VM, then re-run:
   ```nu
   ansible-playbook ansible/setup.yml --ask-become-pass --tags defaults
   ```
   This applies the hardened `orbstack_config` settings (disabling LAN port exposure, SSH port exposure, Kubernetes, and Time Machine backups).
5. **BetterDisplay**: Launch BetterDisplay, activate your licence (if Pro), and assign your monitor's physical DDC input source to Slot 1 (the keyboard shortcut and Sparkle privacy flags are already configured).
6. **Optional hardware auth** (when enabled in `custom/config.yml`):
   - **YubiKey**: Register `pamu2fcfg > ~/.config/Yubico/u2f_keys`, load or create a resident FIDO2 SSH key (`ssh-keygen -K`), and re-run `--tags yubikey`.
   - **immurok**: Pair and enrol in the app, turn on strong sudo authentication, and re-run `--tags sudo`.
7. **Account sign-ins & cloud sync**: Run `gh auth login`, sign in to Raycast (Cloud Sync or `.rayconfig`), Tailscale, Google Chrome, and any personal apps in your `custom/Brewfile`; populate `~/.config/private/secrets.env` (`chmod 600`) for secrets loaded via `with-secrets`.

## Architecture: Public Core + Private Overlay

```
groundhog/                        # Public repository
├── ansible/                      # Playbook, bootstrap, and roles
│   ├── bootstrap.sh
│   ├── setup.yml
│   ├── vars/default.config.yml   # Clean, opt-in defaults
│   └── roles/                    # sudo, homebrew, macos_defaults, dock, dev_tools, yubikey, immurok
├── custom.example/               # Ready-to-copy starter template for private overlays
├── custom/                       # Git-ignored private overlay repo (e.g. groundhog-private)
│   ├── config.yml                # Feature flags & Dock overrides
│   ├── Brewfile                  # Personal, hardware, cloud/AI, and MAS packages
│   ├── gitconfig                 # Personal git name/email (linked to ~/.gitconfig.custom)
│   ├── links.conf                # Custom symlinks (SSH hosts, AWS, AI instructions, etc.)
│   ├── copies.conf               # App-managed files (seed + capture)
│   └── tasks.yml                 # Optional extra Ansible tasks
├── homebrew/.Brewfile            # Core formulae, casks, fonts, and VS Code extensions
├── zsh/ git/ tmux/ nvim/ ghostty/ gh/ atuin/ bat/ btop/ lazygit/ vscode/ nushell/ ssh/
├── tests/test_setup.sh           # Verification suite (`make verify`)
└── dotfiles.sh                   # Stow, overlay links, capture, and `init-custom`
```

### Variable & Package Precedence (Lowest → Highest)

1. `ansible/vars/default.config.yml` & `homebrew/.Brewfile` — public core defaults
2. `custom/config.yml` & `custom/Brewfile` — your private overlay repository (shared across your Macs)
3. `ansible/vars/config.yml` & `homebrew/.Brewfile.local` — per-machine untracked overrides (git-ignored)

## Feature Flags

Optional hardware and inbound-access modules are **off by default** in `ansible/vars/default.config.yml`. Enable what you need in `custom/config.yml` or `ansible/vars/config.yml`:

| Flag | Default | What it enables |
|------|---------|-----------------|
| `remote_login_enabled` | `false` | Inbound macOS Remote Login with hardened PQC-first `/etc/ssh/sshd_config.d/050-hardening.conf` and Mosh firewall rules |
| `mosh_enabled` | `true` | Allows Homebrew `mosh-server` through the firewall when `remote_login_enabled` is `true` |
| `yubikey_enabled` | `false` | `yubikey` role + `pam_u2f` sudo integration (when `~/.config/Yubico/u2f_keys` exists) |
| `immurok_enabled` | `false` | `immurok` role (keeps app SSH agent/Quick Fill off) + `pam_immurok` sudo integration |

## Managed Stack Highlights

- **Shell & terminal**: [Nushell](https://www.nushell.sh/) as default interactive shell launched via a `zsh` login shell (`~/.local/bin/interactive-shell`), [Ghostty](https://ghostty.org/), `tmux` + `sesh` (`Ctrl-a T` session picker, `Ctrl-a y` / `cplast` to copy last command output), `oh-my-posh`, `atuin`, `fzf`, `carapace`, `zoxide`, `yazi`, Catppuccin Mocha everywhere.
- **Dev & runtimes**: `uv` (venv-only Python, `pip` blocked outside venvs), `mise` (Node), `ruff`, `ty`, `pyright`, `go`, `bun`, `neovim` (`lazy.nvim`), VS Code (`settings.json`, `keybindings.json`, 24 extensions, and `duti` code/text file associations).
- **Desktop app hardening**: **OrbStack** (`docker.expose_ports_to_lan=false`, `machines.expose_ports_to_lan=false`, `ssh.expose_port=false`), **Shottr** (`Cmd+Shift+3/4/5` + OCR, telemetry off), **BetterDisplay** (portable DDC shortcut + Sparkle telemetry off).
- **Security**: PQC-first SSH (`mlkem768x25519-sha256`), AEAD ciphers (`chacha20-poly1305`, `aes256-gcm`), ETM MACs, Secretive Secure Enclave SSH/signing, macOS Firewall + Stealth Mode, AirPlay Receiver & AirDrop discoverability disabled, 60-second `sudo` cache timeout, and Gitleaks pre-commit hook.

## Secretive (Secure Enclave SSH)

`ssh/.ssh/config` points `IdentityAgent` at Secretive's socket and prefers `~/.ssh/id_secretive.pub` (with optional YubiKey `id_ed25519_sk` break-glass). Both `zsh/.zprofile` and Nushell `env.nu` export `SSH_AUTH_SOCK` when Secretive's socket is present so `git` SSH commit signing works automatically.

On each Mac, open Secretive, enable SecretAgent, create authentication and signing keys (notify-only works smoothly in clamshell mode and over remote SSH), then link both public keys:

```nu
ln -sf ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/PublicKeys/<auth-key>.pub ~/.ssh/id_secretive.pub
ln -sf ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/PublicKeys/<sign-key>.pub ~/.ssh/id_secretive_sign.pub
```

Register both on GitHub:

```nu
gh ssh-key add ~/.ssh/id_secretive.pub --type authentication --title "mac-auth (Secretive)"
gh ssh-key add ~/.ssh/id_secretive_sign.pub --type signing --title "mac-sign (Secretive)"
```

## Commands & Verification

```bash
./dotfiles.sh init-custom  # Scaffold a private overlay git repo in custom/
./dotfiles.sh apply        # Brew install + stow + manual/custom links + tmux plugins
./dotfiles.sh link         # Stow + manual/custom links + tmux plugins (skip brew)
./dotfiles.sh status       # Show link and overlay status
./dotfiles.sh diff         # Show differences between repo and home directory
./dotfiles.sh capture      # Copy app-managed files back into custom/
make verify                # Gitleaks, ShellCheck, ansible-lint, yamllint, tests
```

## Licence

[Unlicense](LICENSE) — Public Domain
