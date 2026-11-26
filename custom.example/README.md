# Private Overlay Template (`custom/`)

This folder is the starter kit for your own private Groundhog overlay repository (for example, `groundhog-private`).

Run `./dotfiles.sh init-custom` from the root of `groundhog`. It copies this folder to `custom/`, initialises a fresh Git repo inside it, and prints the one-liner to push it to your own private repo on GitHub. Because `groundhog` ignores `custom/`, you can pull upstream Groundhog updates whenever you like without merge conflicts.

## What goes where

| File | What to put in it |
|------|-------------------|
| `config.yml` | Feature flags (`remote_login_enabled`, `yubikey_enabled`, `immurok_enabled`), your `dock_apps`, and any other overrides for `ansible/vars/default.config.yml` |
| `Brewfile` | Personal apps, paid/Mac App Store (`mas`) installs, cloud CLIs, AI tools, hardware security packages, and extra VS Code extensions |
| `gitconfig` | Your `user.name` and `user.email` (linked to `~/.gitconfig.custom` via `links.conf`) |
| `links.conf` | Symlinks from `custom/<path>` to `$HOME/<target>` (SSH hosts, `authorized_keys`, AWS config, agent instructions, etc.) |
| `copies.conf` | Files that apps rewrite atomically (seeded by `./dotfiles.sh link`, saved back with `./dotfiles.sh capture`) |
| `tasks.yml` | Optional extra Ansible tasks run under `--tags custom` |
| `AGENTS.md` | Notes for AI coding agents working inside your private overlay |

A local Gitleaks pre-commit config is included so you don't accidentally commit a key or token even to a private repo.
