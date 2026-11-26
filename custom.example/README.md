# Private Overlay Template (`custom/`)

This directory is a starter template for your private Groundhog overlay repository (for example, `groundhog-private`).

Run `./dotfiles.sh init-custom` from the root of `groundhog` to copy this template into `custom/`, initialise a fresh private git repo inside `custom/`, and push it to your own private GitHub repository. Because `custom/` is git-ignored by `groundhog`, you can `git pull` upstream updates forever with zero merge conflicts.

## Files

| File | Purpose |
|------|---------|
| `config.yml` | Overrides any variable from `ansible/vars/default.config.yml` (feature flags, `dock_apps`, etc.) |
| `Brewfile` | Extra Homebrew formulae, casks, Mac App Store (`mas`) apps, and VS Code extensions |
| `gitconfig` | Your personal `user.name`, `user.email`, and git overrides (linked to `~/.gitconfig.custom`) |
| `links.conf` | Symlinks from `custom/<src>` to `$HOME/<target>` (SSH hosts, AWS config, AI agent instructions, etc.) |
| `copies.conf` | App-managed files seeded by `./dotfiles.sh link` and captured back by `./dotfiles.sh capture` |
| `tasks.yml` | Optional extra Ansible tasks run under `--tags custom` |
