# Groundhog

<p align="center">
  <img src="docs/images/groundhog-logo.jpg" alt="Groundhog: automated macOS workstation setup" width="320">
</p>

> Wake up on a brand-new Mac, run one script, and get the exact same desk back.

**Interactive site:** [gofastercloud.github.io/groundhog](https://gofastercloud.github.io/groundhog/) · **Agentic coding guide:** [AGENTIC.md](AGENTIC.md) · **Agent skill:** [skills/groundhog/SKILL.md](skills/groundhog/SKILL.md) · **Changelog:** [CHANGELOG.md](CHANGELOG.md)

Groundhog is a macOS workstation setup built on [Ansible](https://docs.ansible.com/), [Homebrew](https://brew.sh/), [GNU Stow](https://www.gnu.org/software/stow/), and a zero-dependency Python CLI + `curses` TUI (`./groundhog`). It sets up a Nushell-first terminal (Ghostty, tmux, Neovim, Catppuccin Mocha), `uv` and `mise` with 7-day supply-chain cooldowns, post-quantum-first SSH with [Secretive](https://github.com/maxgoedjen/secretive), sensible macOS defaults, VS Code settings and extensions, and hardened OrbStack settings.

The twist is the **`custom/` overlay**. Everything personal (paid apps, Mac App Store installs, homelab SSH hosts, cloud profiles, YubiKey or fingerprint-key plumbing, and your Dock) lives in your own separate private Git repo cloned into `custom/`. Groundhog ignores `custom/`, so you can pull updates from upstream forever without fighting merge conflicts in your Brewfile or worrying about accidentally pushing private config to a public repo.

## How it works

Groundhog layers configuration from generic to specific:

1. **This repo** (`ansible/vars/default.config.yml` and `homebrew/.Brewfile`) gives you a clean, hardware-agnostic base. No Mac App Store sign-in needed, no inbound SSH opened by default, and no niche hardware assumed.
2. **`custom/`** (optional, git-ignored) is your own private repo (for example, `groundhog-private`). Drop a `config.yml`, `Brewfile`, `gitconfig`, `links.conf`, `copies.conf`, or `tasks.yml` in there and both Ansible and `./groundhog` pick them up automatically.
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
  ./groundhog init-custom
  ```
  Edit the files inside `custom/`, validate with `./groundhog verify-custom`, then commit and push to a private repo on GitHub:
  ```bash
  cd custom
  git add -A && git commit -m "Initial private overlay"
  gh repo create groundhog-private --private --source=. --push
  ```
- **Restoring a fresh Mac?** Pass `--custom-repo` straight to `bootstrap.sh` (or clone manually into `~/groundhog/custom`).

### 3. Two quick checks before running `bootstrap.sh`

1. **Give `Terminal.app` Full Disk Access** (*System Settings > Privacy & Security > Full Disk Access*). macOS quietly drops or rejects a handful of settings (Remote Login, Reduce Transparency/Motion, and sandboxed apps like Shottr) unless the terminal running Ansible has it.
2. **Sign in to the Mac App Store** only if you put `mas` entries in your `custom/Brewfile`. The public default Brewfile has none.

### 4. Run the bootstrap

```bash
bash ansible/bootstrap.sh
# Or clone your private overlay automatically during bootstrap:
bash ansible/bootstrap.sh --custom-repo git@github.com:YOUR_USERNAME/groundhog-private.git
```

`bootstrap.sh` installs Xcode Command Line Tools, Homebrew (from a pinned installer commit), GNU Stow, Ansible, and pinned Galaxy collections, then hands off to `./groundhog ansible`. Once linked, `groundhog` is also on your `PATH` at `~/.local/bin/groundhog`.

To launch the interactive `curses` TUI at any time:

```bash
./groundhog
```

Or run non-interactive subcommands directly:

```bash
./groundhog check --tags "defaults"              # Dry-run Ansible (--check --diff)
./groundhog ansible --tags "homebrew,defaults"   # Apply selected tags (single sudo auth)
make apply TAGS="homebrew,defaults,dotfiles"     # Makefile shortcut
```

Just want the dotfiles without Ansible?

```bash
brew install stow
./groundhog link --skip-hooks --skip-tmux --skip-bat
```

### Why `./groundhog ansible` instead of plain `ansible-playbook`?

If you have Touch ID enabled for `sudo`, running `ansible-playbook --ask-become-pass` on macOS pops a Touch ID prompt on every single privileged task (Ansible isolates workers with `os.setsid()`, which breaks macOS's per-TTY `sudo` cache).

`./groundhog ansible` sidesteps that without weakening `sudo` with `NOPASSWD`: it enables `pipelining = True`, stages a `visudo`-checked temporary drop-in (`Defaults timestamp_type=global`) inside root-owned `/etc/sudoers.d/`, refreshes your ticket while the playbook runs, and deletes the drop-in plus runs `sudo -k` the moment the playbook exits or is interrupted.

## Local verification & Git hooks

Verification is **local-first** (no paid GitHub Actions CI required; GitHub Actions only publishes the static Docs/Pages site). Local `pre-commit` and `pre-push` hooks act as the gate:

```bash
make doctor   # Check required lint/test tools and print any missing brew install line
make hooks    # Install pre-commit + pre-push hooks in groundhog (and custom/ when present)
make verify   # Run pre-commit, ruff, ty, pytest, test_setup.sh, nu check, ansible-lint & verify-custom
```

Missing tools **fail** `make verify` by default so you never get a false green (pass `ALLOW_SKIP=1` to opt out explicitly). On `git push`, `pre-push` runs Gitleaks across the full pushed commit range (`origin/main..HEAD`) plus `make verify`.

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
   - Create an authentication key and a commit-signing key. *(Tip: if you use your Mac in clamshell mode or work over remote SSH, choose **Notify** rather than **Require Authentication** — see [SECURITY.md](SECURITY.md) for the trade-off.)*
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
4. **OrbStack**: Open `OrbStack.app` once so it finishes initialising its CLI, then run `./groundhog ansible --tags defaults` to lock down LAN/SSH port exposure and backups.
5. **BetterDisplay**: Open it, activate your licence if you use Pro, and bind your monitor's DDC input to Slot 1 (the shortcut and privacy settings are already applied).
6. **Optional hardware auth** (only if you enabled `yubikey_enabled` or `immurok_enabled` in `custom/config.yml`):
   - **YubiKey**: run `pamu2fcfg | save ~/.config/Yubico/u2f_keys`, run `ssh-keygen -K` to load a resident break-glass key, then `./groundhog ansible --tags yubikey`.
   - **immurok**: pair and enrol in the app, turn on strong sudo auth in Settings, then `./groundhog ansible --tags sudo`.
7. **Account sign-ins**: `gh auth login`, Raycast (Cloud Sync or `.rayconfig`), Tailscale, Chrome, and your chosen secrets manager (1Password, Keychain, etc.) for any personal API keys.

## What is included

- **Terminal & shell**: [Nushell](https://www.nushell.sh/) as the default interactive shell, launched from a lean `zsh` login shell (`~/.local/bin/interactive-shell`) so `PATH`, `mise` shims, `JAVA_HOME`, and `SSH_AUTH_SOCK` work consistently in Ghostty, tmux, and VS Code. `zsh` stays available as a minimal fallback (`DOTFILES_SHELL=zsh`). Includes Ghostty, pinned tmux plugins + `sesh` (`Ctrl-a T` session picker, `Ctrl-a y` or `cplast` to copy the last command's output), `oh-my-posh`, `atuin`, `fzf`, `carapace`, `zoxide`, and `yazi`.
- **Editors & runtimes**: Neovim (`lazy.nvim`), VS Code (`settings.json`, `keybindings.json`, 24 extensions, and `duti` code/text file associations), `uv` for Python (7-day `exclude-newer` cooldown, `pip` blocked outside virtualenvs), `mise` for Node (7-day `minimum_release_age` cooldown), `npm` (`ignore-scripts=true` + 7-day `min-release-age`), `ruff`, `ty`, `pyright`, `go`, and `bun`.
- **Desktop app defaults**: OrbStack (`docker.expose_ports_to_lan=false`, `machines.expose_ports_to_lan=false`, `ssh.expose_port=false`), Shottr (`Cmd+Shift+3/4/5` + OCR, telemetry off), and BetterDisplay (portable DDC shortcut, Sparkle profile info off).
- **Security**: PQC-first SSH (`mlkem768x25519-sha256`), AEAD-only ciphers, ETM-only MACs, Secretive agent integration, macOS Application Firewall + Stealth Mode, AirPlay Receiver and AirDrop discoverability off, 60-second `sudo` cache, global Git `init.templateDir` Gitleaks hook, and local pre-commit/pre-push secret scanning.

### Optional feature flags

Off by default in `ansible/vars/default.config.yml`; turn on what you use in `custom/config.yml`:

| Flag | Default | What it does |
|------|---------|--------------|
| `remote_login_enabled` | `false` | Enables macOS Remote Login with `/etc/ssh/sshd_config.d/050-hardening.conf` (loads ahead of Apple's `100-macos.conf` so PQC KEX wins) |
| `mosh_enabled` | `true` | Allows Homebrew `mosh-server` through the firewall when `remote_login_enabled` is on |
| `claude_code_enabled` | `false` | Merges Seatbelt sandboxing, widened secret-path & force-push deny rules, and a `ruff` hook into `~/.claude/settings.json` |
| `antigravity_enabled` | `false` | Templates `~/.gemini/antigravity-cli/settings.json` with `trustedWorkspaces` |
| `codex_enabled` | `false` | Scaffolds hardened `~/.codex/config.toml` (`workspace-write` sandbox, `network_access = false`, `core` env filtering) and links the Groundhog skill |
| `agent_git_enabled` | `false` | Configures `~/.config/groundhog/agent-git.json`, installs `agent-git`/`agent-gh` 1-hour single-repo GitHub App wrappers, and links `skills/agent-git` |
| `yubikey_enabled` | `false` | Enables the `yubikey` role and `pam_u2f` sudo auth (once `~/.config/Yubico/u2f_keys` exists) |
| `immurok_enabled` | `false` | Enables the `immurok` role (keeps its SSH agent and Quick Fill off) and `pam_immurok` sudo auth |

## Everyday commands

```bash
./groundhog                 # Launch interactive curses TUI (when attached to a terminal)
./groundhog ansible         # Run Ansible with single-auth sudo keepalive (forwards args)
./groundhog check           # Dry-run Ansible (--check --diff) without modifying the system
./groundhog init-custom     # Scaffold a private overlay repo in custom/
./groundhog verify-custom   # Validate custom/ YAML, manifests, SSH keys, and hooks
./groundhog link            # Reconcile stow links, custom links, app copies, and hooks
./groundhog unlink          # Unstow all Stow-managed dotfile packages
./groundhog status          # Show what is linked and whether custom/ is active
./groundhog diff            # Diff repo configs against your live home directory
./groundhog capture         # Pull app-managed files (copies.conf) back into custom/
make doctor                 # Check required verification tools
make hooks                  # Install pre-commit and pre-push hooks
make verify                 # Run full verification suite (strict; ALLOW_SKIP=1 to opt out)
make vm-test                # Headless end-to-end repeatability test in a disposable Tart macOS VM
```

*(A thin `./dotfiles.sh` shim forwards all commands to `./groundhog` for backwards compatibility.)*

## Troubleshooting

- **GNU Stow reports an existing file conflict:** Move or remove the conflicting file in `$HOME` (or inspect it with `./groundhog diff`), then re-run `./groundhog link`.
- **Nushell init scripts feel stale after a `brew upgrade`:** Run `nu-refresh` inside Nushell and open a fresh pane.
- **tmux changes not showing up:** Press `Ctrl-a r` or run `tmux source ~/.tmux.conf`. To re-fetch pinned plugins, press `Ctrl-a I` or re-run `./groundhog link`.
- **Neovim plugins broken after an update:** Run `rm -rfp ~/.local/share/nvim ~/.local/state/nvim` and launch `nvim` to reinstall cleanly from `lazy-lock.json`.
- **Need a package uploaded within the last 7 days:** Override the cooldown for one command:
  - `uv`: `uv sync --exclude-newer false`
  - `mise`: `MISE_MINIMUM_RELEASE_AGE=0s mise install`
  - `npm`: `npm install --min-release-age=0`

## Standing on good shoulders

Groundhog is mostly glue around projects that do the actual work: [Ansible](https://docs.ansible.com/), [Homebrew](https://brew.sh/), [GNU Stow](https://www.gnu.org/software/stow/), [Nushell](https://www.nushell.sh/), [Ghostty](https://ghostty.org/), [Neovim](https://neovim.io/), [Secretive](https://github.com/maxgoedjen/secretive), [OrbStack](https://orbstack.dev/), [Catppuccin](https://catppuccin.com/), [mise](https://mise.jdx.dev/), and [uv](https://docs.astral.sh/uv/). Thanks to all of them.

## Licence

[Unlicense](LICENSE) (Public Domain). Fork it, strip it down, make it yours.
