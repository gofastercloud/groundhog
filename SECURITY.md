# Security Policy

Groundhog manages shell startup files, SSH/SSHD configuration, `sudo` PAM rules, package manager policy, and macOS firewall settings, so security bugs here matter.

## What we care about

- Insecure defaults in `ssh/.ssh/config`, `sshd-hardening.conf.j2`, `roles/sudo`, `roles/claude_code`, or `orbstack.yml`
- Anything that could break `sudo` / PAM lock-in or accidentally widen `NOPASSWD` access
- Unsafe shell quoting, unpinned remote checkouts, or symlink-following issues in `src/groundhog/`, `ansible/bootstrap.sh`, or Ansible tasks
- Hardcoded paths, personal identifiers, or missing `.gitignore` patterns that could cause someone to commit secrets

## Reporting an issue

- For normal hardening suggestions or non-sensitive bugs, please open a public GitHub issue with the affected file(s) and what you expected to happen.
- If you spot a live secret, credential, or sensitive vulnerability, please use GitHub's private vulnerability reporting (enabled on this repository) so it can be rotated straight away.

## Security design notes

- **No secrets in Git (and no bundled plaintext secrets file)**: Private keys, `.env` files, and `gh` auth tokens (`hosts.yml`) are git-ignored. [Gitleaks](https://github.com/gitleaks/gitleaks) runs locally on staged changes (`pre-commit`), across pushed commit ranges (`pre-push`), and automatically on every new `git init` repo via `~/.config/git/template/hooks/pre-commit`. Groundhog intentionally does **not** manage runtime API keys — use your own secrets manager (1Password CLI `op run`, macOS Keychain, `sops`, etc.) outside Git.
- **Hardware-bound SSH**: SSH defaults prefer [Secretive](https://github.com/maxgoedjen/secretive) Secure Enclave keys (non-exportable) with optional FIDO2 break-glass, PQC-first key exchange (`mlkem768x25519-sha256`), AEAD-only ciphers, ETM-only MACs, and `ForwardAgent no`.
- **Supply-chain guardrails**: 7-day release cooldowns in `uv` (`exclude-newer = "7 days"`), `mise` (`minimum_release_age = "7d"`), and `npm` (`min-release-age=7` + `ignore-scripts=true`), venv-only `pip`, `git` `fsckObjects=true`, pinned tmux plugins, pinned Ansible Galaxy collection (`13.2.0`), pinned Homebrew installer commit, and SRI-pinned Three.js on the docs site.
- **Fail-safe `sudo` & PAM**: `/etc/pam.d/sudo_local` is rendered atomically from a single template, checked for missing `.so` paths before and after writing, and never edits `/etc/pam.d/sudo` directly. Deleting `/etc/pam.d/sudo_local` from a root shell restores stock macOS `sudo`. `./groundhog ansible` never uses `NOPASSWD`; its temporary `timestamp_type=global` drop-in is staged inside root-owned `/etc/sudoers.d/` (`umask 0377`), validated with `visudo`, and removed on exit along with `sudo -k`.
- **Clean separation of private data**: Personal configs live in a separate git-ignored `custom/` repository, never mixed into public commit history.

## Threat model & explicit trade-offs

| Control / Choice | What it protects against | Explicit trade-off / residual risk |
|---|---|---|
| **Secretive Notify-only keys** *(optional ergonomics)* | Exfiltration of private key material (keys never leave the Secure Enclave). | Any process launched inside a terminal holding TCC/socket access can silently request a signature or SSH auth; you see a macOS notification *after* use. Choose **Require Authentication** in Secretive if you do not need clamshell or remote SSH convenience. |
| **`./groundhog ansible` global `sudo` window** | Touch ID prompt spam during Ansible runs without resorting to `NOPASSWD: ALL`. | For the 1–5 minutes the playbook runs, `Defaults timestamp_type=global` lets any process running as your user invoke `sudo` without re-authenticating. Close untrusted agents before running Ansible. |
| **Agent deny lists (`roles/claude_code`)** | Accidental reads/writes of `~/.ssh`, `~/.aws`, `.env`, and destructive `git push` flags. | Deny lists are soft guardrails, not hard OS walls; a shell command outside Seatbelt could bypass them. Pair with Secretive hardware keys and `agent-box` for untrusted repos. |
| **No bundled secrets manager** | Eliminates plaintext `~/.config/private/secrets.env` files readable by any local process. | You supply your own secrets workflow (`op run`, Keychain, `sops`/`age`, etc.) outside Groundhog. |
| **7-day package cooldowns (`uv`, `mise`, `npm`)** | Freshly published supply-chain malware (TeamPCP-style attacks). | Legitimate brand-new releases need an explicit ad-hoc override (`uv ... --exclude-newer false`, `MISE_MINIMUM_RELEASE_AGE=0s`, `npm --min-release-age=0`). |
