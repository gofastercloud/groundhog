# Contributing to Groundhog

Thanks for taking an interest! Groundhog started as a personal macOS setup and grew into something clean enough to share. Bug fixes, macOS compatibility improvements, clearer docs, and sensible defaults are always welcome.

## Before opening a PR

- **Keep the public repo generic.** Personal packages, paid/Mac App Store apps, private hostnames, work accounts, and hardware-specific quirks belong in a user's `custom/` overlay, not here. If a feature is useful to some people but not everyone (like YubiKey or Remote Login), put it behind a boolean flag in `ansible/vars/default.config.yml` defaulted to `false`.
- **Guard optional tools.** Check `command -v` or `/Applications/<App>.app` so configs degrade quietly on machines that don't have a given tool installed.
- **No hardcoded user paths.** Use `$HOME`, `~`, or Ansible's `{{ home_dir }}`.
- **Keep stateful folders unfolded.** Packages like `git`, `gh`, `vscode`, and `nushell` use `stow --no-folding` so caches, auth tokens, and history stay outside the repo.
- **Never commit secrets.** Gitleaks runs locally on staged changes (`pre-commit`) and across pushed commit ranges (`pre-push`). See [SECURITY.md](SECURITY.md).

## How to contribute

Verification is **local-first** via Git hooks rather than hosted CI, so install the hooks before making changes:

1. Fork the repo and branch from `main`.
2. Check your local verification tools and install both `pre-commit` and `pre-push` hooks:
   ```bash
   make doctor
   make hooks
   ```
3. Make small, focused commits (signed commits are required on `main`).
4. Update `tests/test_setup.sh` and `tests/test_groundhog.py` if you added or changed a CLI behaviour, config invariant, role, or Brewfile entry.
5. Run the full strict check suite and make sure everything passes:
   ```bash
   make verify
   ```
   This runs `pre-commit` (Gitleaks, ShellCheck, `yamllint`, `ruff`, `ty`, hardcoded-path check), `pytest`, `tests/test_setup.sh`, the Nushell startup check, Ghostty/tmux/Neovim config validation, Ansible syntax & lint checks (`production` profile), and `verify-custom`.
6. Open a pull request explaining **what** changed and **why**.

## Adding a new Stow package

Create a top-level directory named after the tool mirroring `$HOME` (for example, `bat/.config/bat/config`), add the directory name to `STOW_PACKAGES` in `src/groundhog/config.py` and `STATIC_TARGETS` in `src/groundhog/ops.py` (plus `NO_FOLDING_PACKAGES` if the target directory holds runtime state), and run `make verify`.

Not sure whether a change fits the public core? Open a short issue first and we can talk it through before you spend time coding.
