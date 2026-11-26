# Contributing

This is a personal dotfiles repository, but contributions are welcome -- especially bug fixes, improvements to existing configs, and new tool configurations that fit the repo's style.

## How to Contribute

1. Fork the repository.
2. Create a feature branch from `main`.
3. Make your changes and commit (see conventions below).
4. Open a pull request against `main`.

Commit signing is required. Branch protection is enabled on `main`, so unsigned commits will be rejected.

## Stow Package Structure

Each top-level directory is a [GNU Stow](https://www.gnu.org/software/stow/) package that mirrors the home directory structure. For example:

```
zsh/.zshrc           ->  ~/.zshrc
nvim/.config/nvim/   ->  ~/.config/nvim/
```

When adding a new tool configuration, create a directory at the repo root named after the tool, and place files inside it at the path they would occupy relative to `$HOME`. Then add the package name to the `STOW_PACKAGES` array in `dotfiles.sh`.

## Guidelines

- **Keep configs tool-agnostic where possible.** Guard tool-specific logic with `command -v` checks so configs degrade gracefully on machines where a tool is not installed.
- **Machine-specific configuration belongs in `.local` files.** Examples: `~/.zshrc.local`, `~/.Brewfile.local`. These are git-ignored and sourced or included by the tracked configs.
- **Do not commit secrets.** See `SECURITY.md` for details. The Gitleaks pre-commit hook scans staged changes.
- **Test your changes.** Run `make verify` (runs Gitleaks, ShellCheck, `ansible-lint`, `yamllint`, Nushell startup checks, and `./tests/test_setup.sh`). Run `./dotfiles.sh link` only when you intend to reconcile the live home directory.

## Questions

If you are unsure whether a change fits, open an issue first to discuss it.
