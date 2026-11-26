# AGENTS.md — Private Groundhog Overlay (`custom/`)

This repository is a **private overlay** cloned into `groundhog/custom/` (git-ignored by the public `groundhog` repo). See `../AGENTS.md` for the core Groundhog rules.

## What Belongs Here

- `config.yml` — Feature flags (`remote_login_enabled`, `yubikey_enabled`, `immurok_enabled`), custom `dock_apps`, and overrides for `../ansible/vars/default.config.yml`.
- `Brewfile` — Personal, hardware-specific, cloud/AI, media, and Mac App Store (`mas`) packages.
- `gitconfig` — Personal `user.name` and `user.email` (linked to `~/.gitconfig.custom`).
- `links.conf` — Symlinks from `custom/<src>` to `$HOME/<target>` (SSH hosts/keys, AWS config, AI instructions, etc.).
- `copies.conf` — App-managed files seeded by `../dotfiles.sh link` and saved back with `../dotfiles.sh capture`.
- `tasks.yml` — Optional extra Ansible tasks (use `{{ dotfiles_dir }}/custom/...` for template paths).

## Guardrails

- **Never commit private keys, tokens, or secrets** — Gitleaks pre-commit scanning is active even in this private repo. Manage runtime API keys with your own secrets manager (such as 1Password CLI, macOS Keychain, or `sops`/`age`) outside Git.
- **Keep generic improvements upstream**: If a change benefits any macOS user and contains no personal data, put it in the parent `groundhog` repo instead of here.
- **After edits**: Run `../groundhog link` (or `../groundhog ansible --tags "<tags>"`) from `..` to reconcile live configs, and `../groundhog verify-custom` plus `pre-commit run --all-files` before committing.
