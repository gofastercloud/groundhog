# Security Policy

Groundhog manages shell startup files, SSH/SSHD configuration, `sudo` PAM rules, and macOS firewall settings, so security bugs here matter.

## What we care about

- Insecure defaults in `ssh/.ssh/config`, `sshd-hardening.conf.j2`, `roles/sudo`, or `orbstack.yml`
- Anything that could break `sudo` / PAM lock-in or accidentally widen `NOPASSWD` access
- Unsafe shell quoting, unpinned remote checkouts, or symlink-following issues in `dotfiles.sh` / Ansible tasks
- Hardcoded paths, personal identifiers, or missing `.gitignore` patterns that could cause someone to commit secrets

## Reporting an issue

- For normal hardening suggestions or non-sensitive bugs, please open a public GitHub issue with the affected file(s) and what you expected to happen.
- If you spot a live secret, credential, or sensitive vulnerability, please use GitHub's private vulnerability reporting (or flag it clearly so it can be rotated straight away).

## Security design notes

- **No secrets in Git**: Private keys, `.env` files, and `gh` auth tokens (`hosts.yml`) are git-ignored, and [Gitleaks](https://github.com/gitleaks/gitleaks) runs locally on staged changes via `pre-commit`. Local API tokens live in `~/.config/private/secrets.env` (`chmod 600`) and are only injected into a single command via `with-secrets`.
- **Hardware-bound SSH**: SSH defaults prefer [Secretive](https://github.com/maxgoedjen/secretive) Secure Enclave keys (non-exportable) with optional FIDO2 break-glass, PQC-first key exchange (`mlkem768x25519-sha256`), AEAD-only ciphers, ETM-only MACs, and `ForwardAgent no`.
- **Fail-safe `sudo` & PAM**: `/etc/pam.d/sudo_local` is rendered atomically from a single template, checked for missing `.so` paths before and after writing, and never edits `/etc/pam.d/sudo` directly. Deleting `/etc/pam.d/sudo_local` from a root shell restores stock macOS `sudo`. `./dotfiles.sh ansible` never uses `NOPASSWD`; its temporary `timestamp_type=global` drop-in is validated with `visudo` and removed on exit along with `sudo -k`.
- **Clean separation of private data**: Personal configs live in a separate git-ignored `custom/` repository, never mixed into public commit history.
