# Changelog

All notable changes to Groundhog are documented here. Tag releases (`git tag -s vX.Y.Z`) to create rollback points before major workstation upgrades.

## [0.2.0] - 2026-11-26

### Added
- **Python CLI & `curses` TUI (`./groundhog`)**: Replaced the 567-line `dotfiles.sh` with a zero-runtime-dependency Python 3.11+ CLI and interactive `curses` TUI (`./groundhog`), keeping `./dotfiles.sh` as a thin compatibility shim and linking `~/.local/bin/groundhog`.
- **Supply-chain cooldowns**: Added 7-day release cooldowns to `uv` (`exclude-newer = "7 days"`), `mise` (`minimum_release_age = "7d"`), and `npm` (`min-release-age=7`, alongside `ignore-scripts=true`).
- **Global Git Gitleaks template**: Added `git/.config/git/template/hooks/pre-commit` wired via `[init] templateDir` so every newly initialised Git repo inherits staged-secret scanning automatically.
- **Bootstrap `--custom-repo` flag**: `ansible/bootstrap.sh --custom-repo <git-url>` clones a private overlay into `custom/` automatically on a fresh Mac.
- **Local-first verification gates**: Added `make doctor`, `make hooks`, `make check` (`--check --diff` dry-run), `make verify-custom`, strict missing-tool failures in `make verify` (with `ALLOW_SKIP=1` opt-out), and `pre-push` Gitleaks range scanning + full verification.
- **Behavioural `pytest` suite (`tests/test_groundhog.py`)**: Tests isolated `$HOME` stowing/linking/capture/unlink, `init-custom`/`verify-custom`, Claude settings merging, tmux scrollback parsing, and TUI state navigation.

### Changed
- **Modular `macos_defaults` & `roles/sudo`**: Split the 758-line `macos_defaults/tasks/main.yml` into focused topic files (`animations.yml`, `dock_prefs.yml`, `performance.yml`, `keyboard.yml`, `privacy.yml`), and deduplicated the pre/post PAM module check into `roles/sudo/tasks/check_pam_modules.yml`.
- **Pinned dependencies**: Pinned all tmux plugins to exact commits/tags, pinned Homebrew's installer to a verified commit SHA, dropped `--upgrade` from `ansible-galaxy collection install`, and added an SRI `sha384` import map for Three.js in `docs/index.html`.
- **Tightened security**: Widened Claude Code baseline deny rules (`--force-with-lease`, `git push +*`, `git push --delete`, and `Edit`/`Write` denies on `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.gnupg`, `~/.config/private`), and moved temporary `sudoers` staging out of `/tmp` into root-owned `/etc/sudoers.d/`.

### Removed
- Removed the bundled `with-secrets` / `~/.config/private/secrets.env` helper and `age` from core defaults — secrets management is deliberately left to each user's preferred secrets manager.
- Removed the GitHub Actions CI workflow (`.github/workflows/ci.yml`); verification now runs locally via `pre-commit` and `pre-push` hooks, while GitHub Pages (`pages.yml`) remains active.

## [0.1.0] - 2026-11-26

### Added
- Initial public release of Groundhog: public core + git-ignored `custom/` private overlay architecture, PQC-first SSH/SSHD (`mlkem768x25519-sha256`), Secretive integration, Nushell-first terminal stack, opt-in `claude_code` and `antigravity` roles, `gwt` + `agent-box`, `AGENTIC.md`, and interactive Catppuccin Mocha GitHub Pages site.
