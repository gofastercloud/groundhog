#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local pattern=$2
    grep -Fq -- "$pattern" "$file" || fail "$file is missing: $pattern"
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    if grep -Fq -- "$pattern" "$file"; then
        fail "$file still contains: $pattern"
    fi
}

assert_manifest_entry() {
    local file=$1
    local kind=$2
    local name=$3
    grep -Eq "^${kind} \"${name}\"([[:space:]]|$)" "$file" || fail "$file is missing $kind entry: $name"
}

assert_no_manifest_entry() {
    local file=$1
    local kind=$2
    local name=$3
    if grep -Eq "^${kind} \"${name}\"([[:space:]]|$)" "$file"; then
        fail "$file still contains $kind entry: $name"
    fi
}

assert_ssh_option() {
    local file=$1
    local host=$2
    local option=$3
    local expected=$4
    local actual
    actual=$(ssh -T -F "$file" -G "$host" | awk -v key="$option" '$1 == key { print $2; exit }')
    [[ "$actual" == "$expected" ]] || fail "$host $option must be $expected, got $actual"
}

BREWFILE="$ROOT/homebrew/.Brewfile"
ZSHRC="$ROOT/zsh/.zshrc"
GHOSTTY_CONFIG="$ROOT/ghostty/.config/ghostty/config"
LAUNCHER_TEMPLATE="$ROOT/ansible/roles/dev_tools/templates/ghostty-tmux.j2"
GROUNDHOG_BIN="$ROOT/groundhog"
DOTFILES_SHIM="$ROOT/dotfiles.sh"
HOMEBREW_ROLE="$ROOT/ansible/roles/homebrew/tasks/main.yml"
DEV_TOOLS_ROLE="$ROOT/ansible/roles/dev_tools/tasks/main.yml"
MACOS_DEFAULTS_ROLE="$ROOT/ansible/roles/macos_defaults/tasks/main.yml"
PRIVACY_ROLE="$ROOT/ansible/roles/macos_defaults/tasks/privacy.yml"
REMOTE_LOGIN_ROLE="$ROOT/ansible/roles/macos_defaults/tasks/remote_login.yml"
POWER_ROLE="$ROOT/ansible/roles/macos_defaults/tasks/power.yml"
YUBIKEY_ROLE="$ROOT/ansible/roles/yubikey/tasks/main.yml"
SUDO_ROLE="$ROOT/ansible/roles/sudo/tasks/main.yml"
DEFAULT_VARS="$ROOT/ansible/vars/default.config.yml"
TMUX_CONF="$ROOT/tmux/.tmux.conf"
README="$ROOT/README.md"

# Core Brewfile checks (public defaults stay clean of personal/hardware/MAS bloat).
assert_manifest_entry "$BREWFILE" brew shellcheck
assert_manifest_entry "$BREWFILE" brew ansible-lint
assert_manifest_entry "$BREWFILE" brew yamllint
assert_manifest_entry "$BREWFILE" brew mise
assert_manifest_entry "$BREWFILE" brew duti
assert_manifest_entry "$BREWFILE" brew pyright
assert_manifest_entry "$BREWFILE" brew ruff
assert_manifest_entry "$BREWFILE" brew ty
assert_manifest_entry "$BREWFILE" brew ast-grep
assert_manifest_entry "$BREWFILE" brew difftastic
assert_manifest_entry "$BREWFILE" brew typescript-language-server
assert_manifest_entry "$BREWFILE" brew sesh
assert_manifest_entry "$BREWFILE" cask secretive
assert_manifest_entry "$BREWFILE" cask betterdisplay
assert_manifest_entry "$BREWFILE" cask orbstack
assert_manifest_entry "$BREWFILE" cask shottr
assert_manifest_entry "$BREWFILE" cask ghostty
assert_manifest_entry "$BREWFILE" cask font-ioskeley-mono-term-nerd-font
assert_manifest_entry "$BREWFILE" vscode charliermarsh.ruff
assert_manifest_entry "$BREWFILE" vscode catppuccin.catppuccin-vsc
assert_manifest_entry "$BREWFILE" vscode asvetliakov.vscode-neovim
assert_not_contains "$BREWFILE" 'brew "node"'
if grep -Eq '^mas ' "$BREWFILE"; then
    fail "$BREWFILE must not contain mas entries"
fi
assert_no_manifest_entry "$BREWFILE" brew age
assert_no_manifest_entry "$BREWFILE" brew nvm
assert_no_manifest_entry "$BREWFILE" brew zsh-completions
assert_no_manifest_entry "$BREWFILE" brew zsh-fast-syntax-highlighting
assert_no_manifest_entry "$BREWFILE" cask steam
assert_no_manifest_entry "$BREWFILE" cask claude
assert_no_manifest_entry "$BREWFILE" cask immurok/tap/immurok

# Shell & terminal (lean fallback zsh + primary nushell; no bundled secrets wrapper)
assert_contains "$ZSHRC" 'typeset -U path PATH'
assert_contains "$ZSHRC" 'setopt HIST_IGNORE_SPACE'
assert_contains "$ZSHRC" 'eval "$(mise activate zsh)"'
assert_not_contains "$ZSHRC" 'nvm.sh'
assert_not_contains "$ZSHRC" 'fzf-tab'
assert_not_contains "$ZSHRC" 'zsh-fast-syntax-highlighting'
assert_not_contains "$ZSHRC" 'with-secrets'
assert_not_contains "$ZSHRC" 'source "$HOME/.secrets"'
assert_contains "$ROOT/zsh/.zprofile" 'path=("$HOME/.local/share/mise/shims" $path)'
assert_contains "$ROOT/zsh/.zprofile" 'path=("$HOME/.local/bin" $path)'
assert_not_contains "$ZSHRC" 'path=("$HOME/.local/bin" $path)'
assert_contains "$ZSHRC" "alias gs='git status -sb'"
assert_contains "$ROOT/nushell/Library/Application Support/nushell/autoload/00-aliases.nu" 'alias dcu ='
assert_not_contains "$ROOT/nushell/Library/Application Support/nushell/autoload/utils.nu" 'def --wrapped with-secrets'
assert_contains "$ROOT/zsh/.zprofile" 'com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh'
assert_contains "$ROOT/nushell/Library/Application Support/nushell/env.nu" 'com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh'

# Ghostty, VS Code, Lazygit
assert_contains "$GHOSTTY_CONFIG" 'window-save-state = never'
assert_contains "$GHOSTTY_CONFIG" 'font-family = IoskeleyMonoTerm Nerd Font Mono'
assert_contains "$GHOSTTY_CONFIG" 'command = shell:exec "$HOME/.local/bin/ghostty-tmux"'
assert_contains "$GHOSTTY_CONFIG" 'macos-option-as-alt = true'
assert_not_contains "$GHOSTTY_CONFIG" '/Users/'
assert_not_contains "$GHOSTTY_CONFIG" 'initial-command'
VSCODE_SETTINGS="$ROOT/vscode/Library/Application Support/Code/User/settings.json"
assert_contains "$VSCODE_SETTINGS" '"editor.fontFamily": "IoskeleyMonoTerm Nerd Font Mono"'
assert_contains "$VSCODE_SETTINGS" '"security.workspace.trust.untrustedFiles": "prompt"'
assert_contains "$VSCODE_SETTINGS" '"editor.defaultFormatter": "charliermarsh.ruff"'
assert_not_contains "$VSCODE_SETTINGS" '/Users/'
assert_not_contains "$VSCODE_SETTINGS" 'chatgpt.'
assert_contains "$ROOT/lazygit/.config/lazygit/config.yml" 'delta --dark --paging=never'
assert_contains "$LAUNCHER_TEMPLATE" 'PATH="/opt/homebrew/bin:${PATH:-}"'
assert_not_contains "$LAUNCHER_TEMPLATE" 'sesh connect main'

# CLI, stow, gitignore & supply-chain guards
[[ -x "$GROUNDHOG_BIN" ]] || fail "groundhog launcher must be executable"
[[ -x "$DOTFILES_SHIM" ]] || fail "dotfiles.sh compatibility shim must be executable"
[[ -x "$ROOT/git/.config/git/template/hooks/pre-commit" ]] || fail "global git template pre-commit hook must be executable"
assert_contains "$ROOT/ansible.cfg" 'pipelining = True'
assert_contains "$ROOT/ansible/bootstrap.sh" '--custom-repo'
assert_not_contains "$ROOT/ansible/bootstrap.sh" '/Homebrew/install/HEAD/'
assert_not_contains "$ROOT/ansible/bootstrap.sh" 'collection install -r "${SCRIPT_DIR}/requirements.yml" -p "$HOME/.ansible/collections" --upgrade'
assert_not_contains "$ROOT/ansible/bootstrap.sh" '--upgrade'
git -C "$ROOT" check-ignore -q "custom/config.yml" || fail "custom/ overlay must be gitignored"
git -C "$ROOT" check-ignore -q "vscode/Library/Application Support/Code/User/globalStorage/state.vscdb" || fail "VS Code storage must be gitignored"
git -C "$ROOT" check-ignore -q "vscode/Library/Application Support/Code/User/settings.json" && fail "VS Code settings.json must stay tracked"

# Supply-chain cooldowns (uv, mise, npm) & global Git hardening
assert_contains "$ROOT/ansible/roles/dev_tools/templates/uv.toml.j2" 'exclude-newer = "7 days"'
assert_contains "$ROOT/ansible/roles/dev_tools/templates/mise.toml.j2" 'minimum_release_age = "7d"'
assert_contains "$ROOT/ansible/roles/dev_tools/templates/npmrc.j2" 'ignore-scripts=true'
assert_contains "$ROOT/ansible/roles/dev_tools/templates/npmrc.j2" 'min-release-age=7'
assert_contains "$ROOT/git/.gitconfig" 'fsckObjects = true'
assert_contains "$ROOT/git/.gitconfig" 'allow = user'
assert_contains "$ROOT/git/.gitconfig" 'templateDir = ~/.config/git/template'

# Ansible defaults, feature flags & hardening
assert_not_contains "$HOMEBREW_ROLE" 'failed_when: false'
assert_not_contains "$ROOT/ansible/roles/dock/tasks/main.yml" 'failed_when: false'
assert_not_contains "$MACOS_DEFAULTS_ROLE" 'ignore_errors: true'
assert_contains "$HOMEBREW_ROLE" 'brew bundle check --no-upgrade'
assert_contains "$HOMEBREW_ROLE" 'brew bundle install --no-upgrade'
assert_contains "$HOMEBREW_ROLE" 'custom/Brewfile'
assert_contains "$ROOT/ansible/setup.yml" 'ansible_python_interpreter: "{{ ansible_playbook_python }}"'
assert_contains "$ROOT/ansible/setup.yml" 'custom/config.yml'
assert_contains "$ROOT/ansible/setup.yml" 'custom/tasks.yml'
assert_contains "$DEV_TOOLS_ROLE" 'src: uv.toml.j2'
assert_contains "$DEV_TOOLS_ROLE" 'src: pip.conf.j2'
assert_contains "$DEV_TOOLS_ROLE" 'src: npmrc.j2'
assert_contains "$DEV_TOOLS_ROLE" 'src: mise.toml.j2'
assert_contains "$DEV_TOOLS_ROLE" 'cmd: mise install --yes'

# Optional hardware/SSH/agent features default to false in public repo.
assert_contains "$DEFAULT_VARS" 'remote_login_enabled: false'
assert_contains "$DEFAULT_VARS" 'yubikey_enabled: false'
assert_contains "$DEFAULT_VARS" 'immurok_enabled: false'
assert_contains "$DEFAULT_VARS" 'claude_code_enabled: false'
assert_contains "$DEFAULT_VARS" 'antigravity_enabled: false'
CLAUDE_TEMPLATE="$ROOT/ansible/roles/claude_code/templates/baseline-settings.json.j2"
assert_contains "$CLAUDE_TEMPLATE" '"allowUnsandboxedCommands": false'
assert_contains "$CLAUDE_TEMPLATE" '"Bash(git push --force-with-lease:*)"'
assert_contains "$CLAUDE_TEMPLATE" '"Edit(~/.ssh/**)"'
assert_contains "$CLAUDE_TEMPLATE" '"Write(~/.aws/**)"'
assert_contains "$ROOT/ansible/roles/antigravity/templates/agy-settings.json.j2" 'antigravity_trusted_workspaces'
assert_contains "$ROOT/nushell/Library/Application Support/nushell/autoload/git.nu" '.worktreeinclude'
assert_contains "$ROOT/nushell/Library/Application Support/nushell/autoload/orb.nu" 'def agent-box'
[[ -f "$ROOT/AGENTIC.md" ]] || fail "missing AGENTIC.md"
[[ -f "$ROOT/CHANGELOG.md" ]] || fail "missing CHANGELOG.md"
[[ -f "$ROOT/skills/groundhog/SKILL.md" ]] || fail "missing skills/groundhog/SKILL.md"
assert_contains "$ROOT/skills/groundhog/SKILL.md" 'name: groundhog'
[[ -f "$ROOT/docs/index.html" ]] || fail "missing docs/index.html"
assert_contains "$ROOT/docs/index.html" 'sha384-GY5FqjttLCFRt/McQbyaVdCk2O1IQtOeX8Py6NfD89BIAsIyJFRl4UgSXrk2vXAk'
assert_contains "$DEFAULT_VARS" 'docker.expose_ports_to_lan: "false"'
assert_contains "$DEFAULT_VARS" 'betterdisplay_shortcuts:'

# Modular macos_defaults topic files
for f in animations.yml dock_prefs.yml performance.yml finder.yml keyboard.yml privacy.yml remote_login.yml file_handlers.yml shottr.yml betterdisplay.yml orbstack.yml power.yml; do
    [[ -f "$ROOT/ansible/roles/macos_defaults/tasks/$f" ]] || fail "missing macos_defaults task file: $f"
    assert_contains "$MACOS_DEFAULTS_ROLE" "include_tasks: $f"
done
assert_contains "$PRIVACY_ROLE" 'Keep Gatekeeper quarantine provenance checks enabled'
assert_contains "$PRIVACY_ROLE" 'key: AirplayRecieverEnabled'
assert_contains "$ROOT/ansible/roles/macos_defaults/tasks/finder.yml" 'key: FXDefaultSearchScope'
assert_contains "$ROOT/ansible/roles/macos_defaults/tasks/file_handlers.yml" 'duti -s com.microsoft.VSCode'
assert_contains "$ROOT/ansible/roles/macos_defaults/tasks/shottr.yml" 'KeyboardShortcuts_area'
assert_contains "$ROOT/ansible/roles/macos_defaults/tasks/betterdisplay.yml" 'SUSendProfileInfo'
assert_contains "$ROOT/ansible/roles/macos_defaults/tasks/orbstack.yml" 'orb config set'
assert_contains "$POWER_ROLE" "when: machine_profile == 'desktop'"
assert_contains "$POWER_ROLE" 'cmd: pmset -a networkoversleep 0'

# PAM order, deduplicated PAM check & sudo validation
SUDO_LOCAL_TEMPLATE="$ROOT/ansible/roles/sudo/templates/sudo_local.j2"
[[ -f "$ROOT/ansible/roles/sudo/tasks/check_pam_modules.yml" ]] || fail "missing check_pam_modules.yml"
assert_contains "$SUDO_ROLE" 'include_tasks: check_pam_modules.yml'
assert_contains "$SUDO_ROLE" 'src: sudo_local.j2'
assert_contains "$SUDO_ROLE" 'dest: /etc/pam.d/sudo_local'
assert_contains "$SUDO_ROLE" 'validate: /usr/sbin/visudo -cf %s'
assert_contains "$YUBIKEY_ROLE" 'when: yubikey_enabled | default(false) | bool'
assert_contains "$TMUX_CONF" 'set -g status-interval 30'
assert_contains "$TMUX_CONF" 'sesh connect'
assert_contains "$TMUX_CONF" 'groundhog tmux-copy-last #{pane_id}'
assert_contains "$TMUX_CONF" 'tmux-battery#43832651ede43f54dcf0588727c1957fe648d57d'
assert_contains "$TMUX_CONF" 'tmux-yank#acfd36e4fcba99f8310a7dfb432111c242fe7392'
pam_order=$(grep -oE 'pam_(reattach|immurok|u2f|tid)\.so' "$SUDO_LOCAL_TEMPLATE" | grep -v '^$' | awk '!seen[$0]++' | tr '\n' ' ')
if [ "$pam_order" != "pam_reattach.so pam_immurok.so pam_u2f.so pam_tid.so " ]; then
    fail "sudo_local.j2 PAM order wrong: $pam_order"
fi

# SSH & SSHD PQC hardening
SSHD_HARDENING_TEMPLATE="$ROOT/ansible/roles/macos_defaults/templates/sshd-hardening.conf.j2"
assert_contains "$REMOTE_LOGIN_ROLE" 'src: sshd-hardening.conf.j2'
assert_contains "$REMOTE_LOGIN_ROLE" 'dest: /etc/ssh/sshd_config.d/050-hardening.conf'
assert_contains "$REMOTE_LOGIN_ROLE" 'cmd: /usr/sbin/sshd -t'
assert_contains "$SSHD_HARDENING_TEMPLATE" 'KexAlgorithms mlkem768x25519-sha256,'
assert_contains "$SSHD_HARDENING_TEMPLATE" 'AuthenticationMethods publickey'
assert_contains "$ROOT/ssh/.ssh/config" 'IdentityAgent ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh'
assert_contains "$ROOT/ssh/.ssh/config" 'KexAlgorithms mlkem768x25519-sha256,'
assert_ssh_option "$ROOT/ssh/.ssh/config" github.com forwardagent no
assert_ssh_option "$ROOT/ssh/.ssh/config" github.com hashknownhosts yes
assert_ssh_option "$ROOT/ssh/.ssh/config" github.com identitiesonly yes

# Git includes custom overlay before per-machine local overrides
assert_contains "$ROOT/git/.gitconfig" 'path = ~/.gitconfig.custom'
assert_contains "$ROOT/git/.gitconfig" 'path = ~/.gitconfig.local'

# custom.example starter template completeness
for f in AGENTS.md README.md .gitignore .pre-commit-config.yaml config.yml Brewfile gitconfig links.conf copies.conf tasks.yml; do
    [[ -f "$ROOT/custom.example/$f" ]] || fail "missing custom.example/$f"
done
[[ -f "$ROOT/AGENTS.md" ]] || fail "missing AGENTS.md"
[[ -f "$ROOT/CLAUDE.md" ]] || fail "missing CLAUDE.md"

# Docs-drift guard: every opt-in feature flag in default.config.yml must be documented in README.md.
while IFS= read -r flag; do
    assert_contains "$README" "$flag"
done < <(grep -Eo '^[a-z0-9_]+_enabled:' "$DEFAULT_VARS" | tr -d ':')

# Shell syntax checks
bash -n "$GROUNDHOG_BIN"
bash -n "$DOTFILES_SHIM"
bash -n "$ROOT/ansible/bootstrap.sh"
bash -n "$ROOT/git/.config/git/template/hooks/pre-commit"
zsh -n "$ZSHRC"
zsh -n "$ROOT/zsh/.zprofile"

# Nushell checks
NU_DIR="$ROOT/nushell/Library/Application Support/nushell"
SHELL_LAUNCHER="$ROOT/ansible/roles/dev_tools/templates/interactive-shell.j2"
for f in env.nu config.nu autoload/00-aliases.nu autoload/10-prompt.nu autoload/git.nu autoload/orb.nu autoload/utils.nu; do
    [[ -f "$NU_DIR/$f" ]] || fail "missing nushell file: $f"
done
assert_contains "$NU_DIR/env.nu" 'file: "mise.nu"'
assert_contains "$NU_DIR/config.nu" 'const MISE_MODULE ='
assert_contains "$NU_DIR/autoload/utils.nu" 'def cplast'
zsh -n "$SHELL_LAUNCHER"
zsh -n "$LAUNCHER_TEMPLATE"
if command -v nu >/dev/null; then
    "$ROOT/tests/nu_startup_check.sh" "$NU_DIR" || fail "nushell config does not load cleanly"
fi

# Every top-level directory is either a stow package or explicitly listed non-package directory.
NON_PACKAGE_DIRS=(ansible custom custom.example docs homebrew skills src ssh tests)
[[ -f "$ROOT/docs/images/groundhog-logo.jpg" ]] || fail "missing docs/images/groundhog-logo.jpg"
stow_packages=$(PYTHONPATH="$ROOT/src" python3 -c 'from groundhog.config import STOW_PACKAGES; print(" ".join(STOW_PACKAGES))')
[[ -n "$stow_packages" ]] || fail "could not read STOW_PACKAGES from groundhog.config"
for dir in "$ROOT"/*/; do
    name=$(basename "$dir")
    if [[ " ${NON_PACKAGE_DIRS[*]} " == *" $name "* ]]; then
        continue
    fi
    [[ " $stow_packages " == *" $name "* ]] || fail "top-level directory $name is neither a stow package nor listed in NON_PACKAGE_DIRS"
done
for name in $stow_packages; do
    [[ -d "$ROOT/$name" ]] || fail "STOW_PACKAGES lists $name but there is no such directory"
done

# Tool-level validation of configs
if command -v ghostty >/dev/null; then
    ghostty +validate-config --config-file="$GHOSTTY_CONFIG" >/dev/null || fail "ghostty config does not validate"
fi

if command -v tmux >/dev/null; then
    tmux_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmuxcheck.XXXXXX")
    for conf in "$ROOT/tmux/.tmux.conf" "$ROOT/tmux/.tmux.mobile.conf"; do
        rc=0
        out=$(tmux -S "$tmux_dir/sock" -f "$conf" start-server \; show-messages \; kill-server 2>&1) || rc=$?
        if [[ "$out" == *"error creating"* || "$out" == *"Operation not permitted"* ]]; then
            echo "SKIP: tmux cannot create a socket here (sandbox?); $conf not validated" >&2
        elif (( rc != 0 )) || [[ "$out" =~ (unknown\ command|unknown\ option|invalid\ option|ambiguous) ]]; then
            rm -rf "$tmux_dir"
            fail "tmux rejects $conf: $out"
        fi
    done
    rm -rf "$tmux_dir"
fi

if command -v nvim >/dev/null; then
    nvim --headless +qa >/dev/null 2>&1 || fail "nvim --headless +qa failed"
fi

if command -v ansible-playbook >/dev/null; then
    ansible-playbook -i localhost, "$ROOT/ansible/setup.yml" --syntax-check >/dev/null
fi

assert_contains "$README" 'init-custom'
echo "Configuration checks passed"
