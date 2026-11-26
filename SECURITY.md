# Security Policy

## What Counts as a Security Issue

For a dotfiles repository, security issues include:

- Accidentally committed secrets (API keys, tokens, passwords)
- Insecure default configurations (overly permissive SSH settings, disabled TLS verification, etc.)
- Sensitive file paths or patterns missing from `.gitignore`

## Reporting

This is a personal dotfiles repo, so there is no need for private vulnerability reporting. If you spot a security issue, please open a GitHub issue describing:

- What the issue is
- Which file(s) are affected
- Suggested fix, if you have one

If the issue involves a live secret that was committed, mention that clearly so it can be rotated and force-pushed promptly.

## Protections in Place

### Gitleaks

This repository runs [Gitleaks](https://github.com/gitleaks/gitleaks) from a local pre-commit hook to block staged secrets. Gitleaks output is redacted by default.

### .gitignore

The following patterns are excluded from version control to prevent accidental commits of sensitive material:

- `*.pem`, `*.key` -- private keys
- `*.env` -- scoped environment files, including the private secrets file

### General Rules

- **Never commit private SSH keys.** The `ssh/.ssh/config` file is tracked, but key files must never be added.
- Machine-specific secrets belong in `~/.config/private/secrets.env` with mode `0600` and are loaded only for an explicit command or subshell.
- Machine-specific Homebrew packages belong in `homebrew/.Brewfile.local` (git-ignored).
