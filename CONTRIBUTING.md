# Contributing to Groundhog

Thanks for taking an interest! Groundhog started as a personal macOS setup and grew into something clean enough to share. Bug fixes, macOS compatibility improvements, clearer docs, and sensible defaults are always welcome.

## Before opening a PR

- **Keep the public repo generic.** Personal packages, paid/Mac App Store apps, private hostnames, work accounts, and hardware-specific quirks belong in a user's `custom/` overlay, not here. If a feature is useful to some people but not everyone (like YubiKey or Remote Login), put it behind a boolean flag in `ansible/vars/default.config.yml` defaulted to `false`.
- **Guard optional tools.** Check `command -v` or `/Applications/<App>.app` so configs degrade quietly on machines that don't have a given tool installed.
- **No hardcoded user paths.** Use `$HOME`, `~`, or Ansible's `{{ home_dir }}`.
- **Keep stateful folders unfolded.** Packages like `gh`, `vscode`, and `nushell` use `stow --no-folding` so caches, auth tokens, and history stay outside the repo.
- **Never commit secrets.** Gitleaks runs as a local pre-commit hook, and CI/local checks will flag anything suspicious. See [SECURITY.md](SECURITY.md).

## How to contribute

1. Fork the repo and branch from `main`.
2. Make small, focused commits (signed commits are strongly encouraged and may be required by branch protection).
3. Update `tests/test_setup.sh` if you added or changed a config invariant, role, or Brewfile entry.
4. Run the full check suite and make sure everything passes:
   ```bash
   make verify
   ```
   This runs Gitleaks, ShellCheck, `ansible-lint` (`production` profile), `yamllint`, the Nushell startup check, Ghostty/tmux/Neovim config validation, Ansible syntax checks, and `tests/test_setup.sh`.
5. Open a pull request explaining **what** changed and **why**.

## Adding a new Stow package

Create a top-level directory named after the tool mirroring `$HOME` (for example, `bat/.config/bat/config`), add the directory name to `STOW_PACKAGES` and `get_targets()` in `dotfiles.sh`, and run `make verify`.

Not sure whether a change fits the public core? Open a short issue first and we can talk it through before you spend time coding.
