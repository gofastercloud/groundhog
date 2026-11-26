# Groundhog

<p align="center">
  <img src="docs/images/groundhog-logo.jpg" alt="Groundhog: automated macOS workstation setup" width="320">
</p>

> Wake up on a brand-new Mac, run one script, and get the exact same desk back.

**Interactive site:** [gofastercloud.github.io/groundhog](https://gofastercloud.github.io/groundhog/) · **Agentic coding guide:** [AGENTIC.md](AGENTIC.md)

Groundhog is a macOS workstation setup built on [Ansible](https://docs.ansible.com/), [Homebrew](https://brew.sh/), and [GNU Stow](https://www.gnu.org/software/stow/). It sets up a Nushell-first terminal (Ghostty, tmux, Neovim, Catppuccin Mocha), `uv` and `mise` for runtimes, post-quantum-first SSH with [Secretive](https://github.com/maxgoedjen/secretive), sensible macOS defaults, VS Code settings and extensions, and hardened OrbStack settings.

The twist is the **`custom/` overlay**. Everything personal (paid apps, Mac App Store installs, homelab SSH hosts, cloud profiles, YubiKey or fingerprint-key plumbing, and your Dock) lives in your own separate private Git repo cloned into `custom/`. Groundhog ignores `custom/`, so you can pull updates from upstream forever without fighting merge conflicts in your Brewfile or worrying about accidentally pushing private config to a public repo.

## How it works

Groundhog layers configuration from generic to specific:

1. **This repo** (`ansible/vars/default.config.yml` and `homebrew/.Brewfile`) gives you a clean, hardware-agnostic base. No Mac App Store sign-in needed, no inbound SSH opened by default, and no niche hardware assumed.
2. **`custom/`** (optional, git-ignored) is your own private repo (for example, `groundhog-private`). Drop a `config.yml`, `Brewfile`, `gitconfig`, `links.conf`, `copies.conf`, or `tasks.yml` in there and both Ansible and `dotfiles.sh` pick them up automatically.
3. **Local files** (`ansible/vars/config.yml`, `homebrew/.Brewfile.local`, `~/.gitconfig.local`, `~/.ssh/config.local`, `~/.zshrc.local`) handle one-off overrides for a single Mac without touching either repo.

## Getting started on a fresh Mac

### 1. Clone Groundhog

```bash
git clone https://github.com/YOUR_USERNAME/groundhog.git ~/groundhog
cd ~/groundhog
```

### 2. Set up your private overlay (optional, recommended)

If you want to try the defaults straight away, skip this step. You can add `custom/` at any time.

- **First time?** Generate a ready-to-push starter repo from `custom.example/`:
  ```bash
  ./dotfiles.sh init-custom
  ```
  Edit the files inside `custom/`, commit them, and push to a private repo on GitHub:
  ```bash
  cd custom
  git add -A && git commit -m "Initial private overlay"
  gh repo create groundhog-private --private --source=. --push
  ```
- **Restoring a fresh Mac?** Clone your private overlay straight into `custom/`:
  ```bash
  git clone git@github.com:YOUR_USERNAME/groundhog-private.git ~/groundhog/custom
  ```

### 3. Two quick checks before running `bootstrap.sh`

1. **Give `Terminal.app` Full Disk Access** (*System Settings > Privacy & Security > Full Disk Access*). macOS quietly drops or rejects a handful of settings (Remote Login, Reduce Transparency/Motion, and sandboxed apps like Shottr) unless the terminal running Ansible has it.
2. **Sign in to the Mac App Store** only if you put `mas` entries in your `custom/Brewfile`. The public default Brewfile has none.

### 4. Run the bootstrap

```bash
bash ansible/bootstrap.sh
```

`bootstrap.sh` installs Xcode Command Line Tools (waiting for the installer dialog to finish), Homebrew, GNU Stow, Ansible, and Galaxy collections, then hands off to `./dotfiles.sh ansible`.

To re-run specific parts later:

```bash
./dotfiles.sh ansible --tags "homebrew,defaults,dotfiles"
# or:
make apply TAGS="homebrew,defaults,dotfiles"
```

Just want the dotfiles without Ansible?

```bash
brew install stow
./dotfiles.sh apply   # Brewfiles + stow + links + tmux plugins
./dotfiles.sh link    # stow + links + tmux plugins only
```

### Why `./dotfiles.sh ansible` instead of plain `ansible-playbook`?

If you have Touch ID enabled for `sudo`, running `ansible-playbook --ask-become-pass` on macOS pops a Touch ID prompt on every single privileged task (Ansible isolates workers with `os.setsid()`, which breaks macOS's per-TTY `sudo` cache).

`./dotfiles.sh ansible` sidesteps that without weakening `sudo` with `NOPASSWD`: it enables `pipelining = True`, writes a `visudo`-checked temporary drop-in (`Defaults timestamp_type=global`), refreshes your ticket while the playbook runs, and deletes the drop-in plus runs `sudo -k` the moment the playbook exits or is interrupted.

## What still needs a human afterwards

macOS deliberately stops scripts from granting privacy permissions, creating Secure Enclave keys, or signing you into accounts. Once `bootstrap.sh` finishes, expect about 10 to 15 minutes of clicking through these:

1. **Log out and back in** (or reboot) so key repeat, menu bar, Finder, and Dock defaults settle in.
2. **Privacy & Security permissions**:
   - *Full Disk Access*: add **Ghostty** so future Ansible runs work from your real terminal.
   - *Screen & System Audio Recording*: allow **Shottr**.
   - *Accessibility*: allow **Raycast** and **BetterDisplay**.
   - *Network Extensions* (*General > Login Items & Extensions*): approve **Tailscale** (and any egress firewall you added to `custom/Brewfile`).
   - Double-check **FileVault**, **Lock Screen** timing, and **Focus** modes.
3. **Secretive (hardware-bound SSH and Git signing)**:
   - Open Secretive and turn on the background SecretAgent.
   - Create an authentication key and a commit-signing key. *(Tip: if you use your Mac in clamshell mode or work over remote SSH, choose **Notify** rather than **Require Authentication** — the private key still never leaves the Secure Enclave.)*
   - Symlink both public keys:
     ```nu
     ln -sf ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/PublicKeys/<auth>.pub ~/.ssh/id_secretive.pub
     ln -sf ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/PublicKeys/<sign>.pub ~/.ssh/id_secretive_sign.pub
     ```
   - Set your Git name and email in `custom/gitconfig` (or `~/.gitconfig.local`), then register both keys on GitHub:
     ```nu
     gh ssh-key add ~/.ssh/id_secretive.pub --type authentication --title "mac-auth (Secretive)"
     gh ssh-key add ~/.ssh/id_secretive_sign.pub --type signing --title "mac-sign (Secretive)"
     ```
4. **OrbStack**: Open `OrbStack.app` once so it finishes initialising its CLI, then run `./dotfiles.sh ansible --tags defaults` to lock down LAN/SSH port exposure and backups.
5. **BetterDisplay**: Open it, activate your licence if you use Pro, and bind your monitor's DDC input to Slot 1 (the shortcut and privacy settings are already applied).
6. **Optional hardware auth** (only if you enabled `yubikey_enabled` or `immurok_enabled` in `custom/config.yml`):
   - **YubiKey**: run `pamu2fcfg | save ~/.config/Yubico/u2f_keys`, run `ssh-keygen -K` to load a resident break-glass key, then `./dotfiles.sh ansible --tags yubikey`.
   - **immurok**: pair and enrol in the app, turn on strong sudo auth in Settings, then `./dotfiles.sh ansible --tags sudo`.
7. **Account sign-ins**: `gh auth login`, Raycast (Cloud Sync or `.rayconfig`), Tailscale, Chrome, and any personal apps in `custom/Brewfile`. Put local API tokens in `~/.config/private/secrets.env` (`chmod 600`) and load them per command with `with-secrets <cmd>`.

## What is included

- **Terminal & shell**: [Nushell](https://www.nushell.sh/) as the default interactive shell, launched from a lean `zsh` login shell (`~/.local/bin/interactive-shell`) so `PATH`, `mise` shims, `JAVA_HOME`, and `SSH_AUTH_SOCK` work consistently in Ghostty, tmux, and VS Code. `zsh` stays available as a minimal fallback (`DOTFILES_SHELL=zsh`). Includes Ghostty, tmux + `sesh` (`Ctrl-a T` session picker, `Ctrl-a y` or `cplast` to copy the last command's output), `oh-my-posh`, `atuin`, `fzf`, `carapace`, `zoxide`, and `yazi`.
- **Editors & runtimes**: Neovim (`lazy.nvim`), VS Code (`settings.json`, `keybindings.json`, 24 extensions, and `duti` code/text file associations), `uv` for Python (with `pip` blocked outside virtualenvs), `mise` for Node, `ruff`, `ty`, `pyright`, `go`, and `bun`.
- **Desktop app defaults**: OrbStack (`docker.expose_ports_to_lan=false`, `machines.expose_ports_to_lan=false`, `ssh.expose_port=false`), Shottr (`Cmd+Shift+3/4/5` + OCR, telemetry off), and BetterDisplay (portable DDC shortcut, Sparkle profile info off).
- **Security**: PQC-first SSH (`mlkem768x25519-sha256`), AEAD-only ciphers, ETM-only MACs, Secretive agent integration, macOS Application Firewall + Stealth Mode, AirPlay Receiver and AirDrop discoverability off, 60-second `sudo` cache, and a local Gitleaks pre-commit hook.

### Optional feature flags

Off by default in `ansible/vars/default.config.yml`; turn on what you use in `custom/config.yml`:

| Flag | Default | What it does |
|------|---------|--------------|
| `remote_login_enabled` | `false` | Enables macOS Remote Login with `/etc/ssh/sshd_config.d/050-hardening.conf` (loads ahead of Apple's `100-macos.conf` so PQC KEX wins) |
| `mosh_enabled` | `true` | Allows Homebrew `mosh-server` through the firewall when `remote_login_enabled` is on |
| `claude_code_enabled` | `false` | Merges Seatbelt sandboxing, secret-path deny rules, and a `ruff` hook into `~/.claude/settings.json` |
| `antigravity_enabled` | `false` | Templates `~/.gemini/antigravity-cli/settings.json` with `trustedWorkspaces` |
| `yubikey_enabled` | `false` | Enables the `yubikey` role and `pam_u2f` sudo auth (once `~/.config/Yubico/u2f_keys` exists) |
| `immurok_enabled` | `false` | Enables the `immurok` role (keeps its SSH agent and Quick Fill off) and `pam_immurok` sudo auth |

## Everyday commands

```bash
./dotfiles.sh ansible      # Run Ansible with single-auth sudo keepalive (forwards args)
./dotfiles.sh init-custom  # Scaffold a private overlay repo in custom/
./dotfiles.sh link         # Reconcile stow links, custom links, and app copies
./dotfiles.sh status       # Show what is linked and whether custom/ is active
./dotfiles.sh diff         # Diff repo configs against your live home directory
./dotfiles.sh capture      # Pull app-managed files (copies.conf) back into custom/
make apply                 # Shortcut for ./dotfiles.sh ansible (supports TAGS="...")
make verify                # Run Gitleaks, ShellCheck, ansible-lint, yamllint, and tests
```

## Standing on good shoulders

Groundhog is mostly glue around projects that do the actual work: [Ansible](https://docs.ansible.com/), [Homebrew](https://brew.sh/), [GNU Stow](https://www.gnu.org/software/stow/), [Nushell](https://www.nushell.sh/), [Ghostty](https://ghostty.org/), [Neovim](https://neovim.io/), [Secretive](https://github.com/maxgoedjen/secretive), [OrbStack](https://orbstack.dev/), [Catppuccin](https://catppuccin.com/), [mise](https://mise.jdx.dev/), and [uv](https://docs.astral.sh/uv/). Thanks to all of them.

## Licence

[Unlicense](LICENSE) (Public Domain). Fork it, strip it down, make it yours.
