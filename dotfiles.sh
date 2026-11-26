#!/usr/bin/env bash
#
# dotfiles.sh - Manage Groundhog dotfiles with GNU Stow and optional custom/ overlay
#
# Usage:
#   ./dotfiles.sh ansible     - Run Ansible playbook with single-auth sudo keepalive
#   ./dotfiles.sh apply       - Full setup: brew, stow, manual/custom symlinks, tmux plugins
#   ./dotfiles.sh link        - Stow configs, manual/custom symlinks, tmux plugins (skip brew)
#   ./dotfiles.sh status      - Show which configs are linked
#   ./dotfiles.sh diff        - Show differences between repo and home
#   ./dotfiles.sh capture     - Copy app-managed files from home back into the repo
#   ./dotfiles.sh brew        - Install Homebrew packages only
#   ./dotfiles.sh init-custom - Initialise a private git repo in custom/ from custom.example/
#

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_DIR="$DOTFILES_DIR/custom"
BACKUP_DIR="$HOME/.backups"

# Packages managed by stow (directory name -> target mapping)
STOW_PACKAGES=(zsh git tmux nvim ghostty gh atuin bat btop lazygit vscode nushell)

TPM_REPO="https://github.com/tmux-plugins/tpm"
TPM_COMMIT="99469c4a9b1ccf77fade25842dc7bafbc8ce9946"

# Core manual symlinks (can't stow because target dirs contain untracked state)
# Format: "absolute_source:absolute_target"
MANUAL_LINKS=(
    "$DOTFILES_DIR/ssh/.ssh/config:$HOME/.ssh/config"
)

# Core app-managed copies (empty by default; custom/copies.conf adds personal entries)
APP_COPIES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 {ansible|apply|link|status|diff|capture|brew|init-custom}"
    echo
    echo "Commands:"
    echo "  ansible     - Run Ansible playbook with a single sudo auth (forwards extra args)"
    echo "  apply       - Full setup: brew packages, stow configs, manual/custom links, tmux plugins"
    echo "  link        - Stow configs, manual/custom links, tmux plugins (skip brew)"
    echo "  status      - Show which configs are currently linked"
    echo "  diff        - Show differences between repo and current configs"
    echo "  capture     - Copy app-managed files from home back into the repo"
    echo "  brew        - Install Homebrew packages only"
    echo "  init-custom - Scaffold a new private overlay git repo in custom/"
    exit 1
}

expand_home() {
    local p=$1
    p="${p/#\~/$HOME}"
    p="${p//\$HOME/$HOME}"
    printf '%s\n' "$p"
}

# Load custom/links.conf and custom/copies.conf when a private overlay is present.
load_custom_manifest() {
    local file=$1
    local array_name=$2
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace and skip blank/comment lines
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        local src="${line%%:*}"
        local target="${line#*:}"
        target=$(expand_home "$target")
        local entry="$CUSTOM_DIR/$src:$target"
        if [[ "$array_name" == "MANUAL_LINKS" ]]; then
            MANUAL_LINKS+=("$entry")
        else
            APP_COPIES+=("$entry")
        fi
    done < "$file"
}

load_custom_manifest "$CUSTOM_DIR/links.conf" MANUAL_LINKS
load_custom_manifest "$CUSTOM_DIR/copies.conf" APP_COPIES

is_managed_link() {
    local link_path=$1
    local target repo_resolved resolved
    target=$(readlink "$link_path")
    repo_resolved=$(cd "$DOTFILES_DIR" && pwd -P)
    if [[ "$target" == "$DOTFILES_DIR"* || "$target" == "$repo_resolved"* ]]; then
        return 0
    fi
    if [[ -e "$link_path" ]]; then
        resolved=$(cd "$(dirname "$link_path")" && cd "$(dirname "$target")" 2>/dev/null && pwd -P || true)
        [[ -n "$resolved" && "$resolved" == "$repo_resolved"* ]] && return 0
    fi
    return 1
}

# Get the target paths for a stow package (for diff/status display)
# One target per line so paths may contain spaces.
get_targets() {
    local pkg=$1
    case $pkg in
        zsh)     printf '%s\n' .zshrc .zprofile ;;
        git)     printf '%s\n' .gitconfig ;;
        tmux)    printf '%s\n' .tmux.conf .tmux.mobile.conf ;;
        nvim)    printf '%s\n' .config/nvim ;;
        ghostty) printf '%s\n' .config/ghostty ;;
        gh)      printf '%s\n' .config/gh/config.yml ;;
        atuin)   printf '%s\n' .config/atuin/config.toml ;;
        bat)     printf '%s\n' .config/bat/config ;;
        btop)    printf '%s\n' .config/btop/btop.conf ;;
        lazygit) printf '%s\n' .config/lazygit ;;
        vscode)  printf '%s\n' "Library/Application Support/Code/User/settings.json" \
                                "Library/Application Support/Code/User/keybindings.json" ;;
        # Stowed with --no-folding, so every file is its own symlink.
        nushell) (cd "$DOTFILES_DIR/nushell" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) ;;
    esac
}

ensure_git_checkout() {
    local repo=$1
    local target=$2
    local commit=$3

    if [[ ! -d "$target/.git" ]]; then
        git clone --filter=blob:none --no-checkout "$repo" "$target"
    fi

    if ! git -C "$target" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$target" fetch --depth 1 origin "$commit"
    fi

    git -C "$target" checkout --quiet --detach "$commit"
}

# Report (and with "seed", create or convert) one app-managed copy.
#   $1 = absolute source, $2 = absolute target, $3 = "seed" (optional)
app_copy_check() {
    local src=$1 target=$2 mode=${3:-}
    if [[ -L "$target" ]]; then
        if [[ "$mode" == "seed" ]]; then
            rm "$target" && cp "$src" "$target"
            echo -e "  ${GREEN}→${NC} $target (symlink replaced with a copy)"
        else
            echo -e "  ${YELLOW}⚠${NC} $target (still a symlink; run link)"
        fi
    elif [[ ! -e "$target" ]]; then
        if [[ "$mode" == "seed" ]]; then
            mkdir -p "$(dirname "$target")" && cp "$src" "$target"
            echo -e "  ${GREEN}→${NC} $target (seeded from repo)"
        else
            echo -e "  ${YELLOW}○${NC} $target (missing)"
        fi
    elif cmp -s "$src" "$target"; then
        echo -e "  ${GREEN}✓${NC} $target (matches repo)"
    else
        echo -e "  ${YELLOW}≠${NC} $target (changed by the app; ./dotfiles.sh capture to save it)"
    fi
}

cmd_capture() {
    echo -e "${BLUE}Capturing app-managed files into the repo...${NC}\n"
    if [[ ${#APP_COPIES[@]} -eq 0 ]]; then
        echo "  (no app-managed copies configured)"
        return 0
    fi
    for entry in "${APP_COPIES[@]}"; do
        local src="${entry%%:*}" target="${entry#*:}"
        if [[ -f "$target" && ! -L "$target" ]]; then
            if cmp -s "$target" "$src"; then
                echo -e "  ${GREEN}✓${NC} $src (unchanged)"
            else
                cp "$target" "$src"
                echo -e "  ${GREEN}→${NC} $src (updated; review with git diff)"
            fi
        else
            echo -e "  ${YELLOW}○${NC} $target (not a plain file; skipped)"
        fi
    done
}

_ANSIBLE_SUDOERS_TMP="/etc/sudoers.d/99-groundhog-ansible"
_ANSIBLE_KEEPALIVE_PID=""

cleanup_ansible_sudo() {
    [[ -n "${_ANSIBLE_KEEPALIVE_PID:-}" ]] && kill "$_ANSIBLE_KEEPALIVE_PID" 2>/dev/null || true
    if [[ -f "$_ANSIBLE_SUDOERS_TMP" ]]; then
        sudo -n rm -f "$_ANSIBLE_SUDOERS_TMP" 2>/dev/null || true
    fi
    sudo -k 2>/dev/null || true
}

cmd_ansible() {
    if ! command -v ansible-playbook &>/dev/null; then
        echo -e "${RED}Error: ansible-playbook is not installed.${NC}" >&2
        echo -e "Run ${YELLOW}bash ansible/bootstrap.sh${NC} first." >&2
        exit 1
    fi

    # Ansible's WorkerProcess calls os.setsid(), detaching each task from the
    # terminal TTY so macOS's default per-TTY sudo cache misses on every task.
    # Temporarily scope the sudo timestamp globally (never NOPASSWD) for the
    # duration of this run, refresh every 30s, and clean up + sudo -k on exit.
    trap cleanup_ansible_sudo EXIT INT TERM

    echo -e "${BLUE}Preparing temporary session-scoped sudo for Ansible...${NC}"
    sudo sh -c '
        set -eu
        tmp=$(mktemp /tmp/groundhog-sudoers.XXXXXX)
        printf "Defaults timestamp_type=global\n" > "$tmp"
        chmod 0440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        chown root:wheel "$tmp"
        mv "$tmp" "$1"
    ' _ "$_ANSIBLE_SUDOERS_TMP"

    # Stamp the global ticket so setsid-detached Ansible workers inherit it.
    sudo -v

    (
        while true; do
            sleep 30
            sudo -n -v 2>/dev/null || exit 0
        done
    ) &
    _ANSIBLE_KEEPALIVE_PID=$!

    ansible-playbook "$DOTFILES_DIR/ansible/setup.yml" "$@"
}

cmd_init_custom() {
    local target="$CUSTOM_DIR"
    local example="$DOTFILES_DIR/custom.example"
    if [[ -e "$target" ]]; then
        echo -e "${RED}Error:${NC} $target already exists. Refusing to overwrite." >&2
        exit 1
    fi
    if [[ ! -d "$example" ]]; then
        echo -e "${RED}Error:${NC} $example template directory not found." >&2
        exit 1
    fi
    cp -R "$example" "$target"
    git -C "$target" init -b main >/dev/null
    echo -e "${GREEN}Initialised private overlay repo at:${NC} $target"
    echo
    echo "Next steps:"
    echo "  1. Customise config.yml, Brewfile, gitconfig, and links.conf inside $target"
    echo "  2. Commit and push to your own private GitHub repository:"
    echo "       cd $target"
    echo "       git add -A && git commit -m 'Initial private overlay'"
    echo "       gh repo create groundhog-private --private --source=. --push"
}

cmd_brew() {
    echo -e "${BLUE}Installing Homebrew packages...${NC}\n"

    if ! command -v brew &>/dev/null; then
        echo -e "${YELLOW}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    echo -e "${GREEN}Installing core packages from homebrew/.Brewfile...${NC}"
    brew bundle install --no-upgrade --file="$DOTFILES_DIR/homebrew/.Brewfile"

    if [[ -f "$CUSTOM_DIR/Brewfile" ]]; then
        echo -e "\n${GREEN}Installing private overlay packages from custom/Brewfile...${NC}"
        brew bundle install --no-upgrade --file="$CUSTOM_DIR/Brewfile"
    fi

    if [[ -f "$DOTFILES_DIR/homebrew/.Brewfile.local" ]]; then
        echo -e "\n${GREEN}Installing machine-specific packages from .Brewfile.local...${NC}"
        brew bundle install --no-upgrade --file="$DOTFILES_DIR/homebrew/.Brewfile.local"
    fi
}

cmd_link() {
    echo -e "${BLUE}Linking dotfiles...${NC}\n"

    # Stow packages
    echo -e "${BLUE}Stowing config packages...${NC}\n"

    if ! command -v stow &>/dev/null; then
        echo -e "${RED}Error: stow is not installed.${NC}"
        echo -e "Install it with: ${YELLOW}brew install stow${NC}"
        echo -e "Or run: ${YELLOW}./dotfiles.sh apply${NC} to install Homebrew and all packages first."
        exit 1
    fi

    mkdir -p "$BACKUP_DIR"

    cd "$DOTFILES_DIR"
    for pkg in "${STOW_PACKAGES[@]}"; do
        if [[ -d "$DOTFILES_DIR/$pkg" ]]; then
            echo -e "  Stowing ${GREEN}$pkg${NC}..."
            while IFS= read -r -d '' entry; do
                local rel="${entry#"$DOTFILES_DIR/$pkg/"}"
                local target="$HOME/$rel"
                if [[ -L "$target" ]] && [[ ! -e "$target" ]]; then
                    echo -e "    ${YELLOW}Removing broken link${NC}: $rel"
                    rm "$target"
                fi
            done < <(find "$DOTFILES_DIR/$pkg" \( -type f -o -type d \) -not -path "$DOTFILES_DIR/$pkg" -print0)
            local stow_output
            local stow_flags=(-v -t "$HOME")
            # Never fold gh, vscode or nushell into directory links: runtime state lives beside config.
            [[ "$pkg" == "gh" ]] && stow_flags+=(--no-folding)
            [[ "$pkg" == "vscode" ]] && stow_flags+=(--no-folding)
            [[ "$pkg" == "nushell" ]] && stow_flags+=(--no-folding)
            if ! stow_output=$(stow "${stow_flags[@]}" "$pkg" 2>&1); then
                echo "$stow_output" >&2
                echo -e "  ${RED}Failed to stow $pkg; resolve the conflict explicitly.${NC}" >&2
                exit 1
            fi
            if [[ -n "$stow_output" ]]; then
                echo "$stow_output" | sed 's/^/    /'
            fi
        fi
    done

    echo

    # Step 3: Manual & custom symlinks
    echo -e "${BLUE}Creating manual & custom symlinks...${NC}\n"
    for entry in "${MANUAL_LINKS[@]}"; do
        local src="${entry%%:*}"
        local target="${entry#*:}"
        local target_dir
        target_dir=$(dirname "$target")

        if [[ ! -e "$src" ]]; then
            echo -e "  ${YELLOW}○${NC} Skipping missing source: $src"
            continue
        fi

        mkdir -p "$target_dir"

        if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$src" ]]; then
            echo -e "  ${GREEN}✓${NC} $target (already linked)"
        else
            [[ -L "$target" ]] && rm "$target"
            if [[ -e "$target" ]]; then
                local backup_name
                backup_name="$(basename "$target").backup.$(date +%s)"
                echo -e "  ${YELLOW}Backing up${NC} $target -> $BACKUP_DIR/$backup_name"
                mv "$target" "$BACKUP_DIR/$backup_name"
            fi
            ln -sfn "$src" "$target"
            echo -e "  ${GREEN}→${NC} $target"
        fi
    done

    echo

    # Step 3b: App-managed copies (seed if missing, never overwrite app changes)
    if [[ ${#APP_COPIES[@]} -gt 0 ]]; then
        echo -e "${BLUE}Checking app-managed copies...${NC}\n"
        for entry in "${APP_COPIES[@]}"; do
            local src="${entry%%:*}" target="${entry#*:}"
            if [[ ! -e "$src" ]]; then
                echo -e "  ${YELLOW}○${NC} Skipping missing source: $src"
                continue
            fi
            app_copy_check "$src" "$target" seed
        done
        echo
    fi

    # Step 4: Repository secret-scanning hook
    echo -e "${BLUE}Installing repository hooks...${NC}\n"
    if ! command -v pre-commit &>/dev/null || ! command -v gitleaks &>/dev/null; then
        echo -e "  ${RED}pre-commit and gitleaks are required.${NC}" >&2
        exit 1
    fi
    pre-commit install --install-hooks
    echo -e "  ${GREEN}✓${NC} Gitleaks pre-commit hook installed"

    echo

    # Step 5: Tmux plugins
    echo -e "${BLUE}Setting up tmux plugins...${NC}\n"
    echo -e "  Installing pinned TPM..."
    ensure_git_checkout "$TPM_REPO" "$HOME/.tmux/plugins/tpm" "$TPM_COMMIT"
    echo -e "  ${GREEN}✓${NC} TPM @ ${TPM_COMMIT:0:12}"
    echo -e "  Installing tmux plugins via TPM..."
    local plugin_output
    if ! plugin_output=$("$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>&1); then
        echo "$plugin_output" >&2
        echo -e "  ${RED}Tmux plugin installation failed.${NC}" >&2
        exit 1
    fi
    echo "$plugin_output" | sed 's/^/    /'

    echo

    # Step 6: Bat cache (for themes)
    echo -e "${BLUE}Rebuilding bat theme cache...${NC}"
    if command bat cache --build >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Done"
    else
        echo -e "  ${RED}Bat cache rebuild failed.${NC}" >&2
        exit 1
    fi

    echo
    echo -e "${GREEN}Linking complete!${NC} Restart your shell: ${YELLOW}exec nu${NC} (or ${YELLOW}exec zsh${NC})"
    echo -e "Then reload tmux: ${YELLOW}tmux source ~/.tmux.conf${NC}"
}

cmd_apply() {
    echo -e "${BLUE}Setting up dotfiles...${NC}\n"

    cmd_brew
    echo
    cmd_link
}

cmd_diff() {
    echo -e "${BLUE}Comparing repo with home directory...${NC}\n"

    for pkg in "${STOW_PACKAGES[@]}"; do
        while IFS= read -r target; do
            local home_file="$HOME/$target"
            local repo_file="$DOTFILES_DIR/$pkg/$target"

            if [[ -e "$repo_file" ]]; then
                echo -e "${YELLOW}=== $target ($pkg) ===${NC}"

                if [[ -L "$home_file" ]]; then
                    if is_managed_link "$home_file"; then
                        echo -e "${GREEN}✓ Linked to repo${NC}"
                    else
                        echo -e "${RED}⚠ Linked elsewhere: $(readlink "$home_file")${NC}"
                    fi
                elif [[ -e "$home_file" ]]; then
                    if [[ -d "$home_file" ]]; then
                        echo -e "${RED}Directory exists (not linked)${NC}"
                    else
                        if diff -q "$home_file" "$repo_file" >/dev/null 2>&1; then
                            echo -e "${GREEN}✓ Identical${NC}"
                        else
                            echo -e "${RED}✗ Different:${NC}"
                            diff --color=auto -u "$home_file" "$repo_file" 2>/dev/null | head -30 || true
                        fi
                    fi
                else
                    echo -e "${YELLOW}○ Not present in home${NC}"
                fi
                echo
            fi
        done < <(get_targets "$pkg")
    done

    echo -e "${YELLOW}=== Manual & Custom Symlinks ===${NC}"
    for entry in "${MANUAL_LINKS[@]}"; do
        local src="${entry%%:*}" target="${entry#*:}"
        if [[ -L "$target" ]]; then
            if [[ "$(readlink "$target")" == "$src" ]]; then
                echo -e "  ${GREEN}✓${NC} $target"
            else
                echo -e "  ${RED}⚠${NC} $target -> $(readlink "$target")"
            fi
        elif [[ -e "$target" ]]; then
            echo -e "  ${RED}✗${NC} $target (exists but not linked)"
        else
            echo -e "  ${YELLOW}○${NC} $target (missing)"
        fi
    done
    echo

    if [[ ${#APP_COPIES[@]} -gt 0 ]]; then
        echo -e "${YELLOW}=== App-managed copies ===${NC}"
        for entry in "${APP_COPIES[@]}"; do
            local src="${entry%%:*}" target="${entry#*:}"
            app_copy_check "$src" "$target"
            if [[ -f "$target" && ! -L "$target" ]] && ! cmp -s "$src" "$target"; then
                diff -u "$src" "$target" | head -40 || true
            fi
        done
        echo
    fi
}

cmd_status() {
    echo -e "${BLUE}Groundhog status:${NC}\n"

    for pkg in "${STOW_PACKAGES[@]}"; do
        echo -e "${YELLOW}[$pkg]${NC}"
        while IFS= read -r target; do
            local home_file="$HOME/$target"

            if [[ -L "$home_file" ]]; then
                if is_managed_link "$home_file"; then
                    echo -e "  ${GREEN}✓${NC} $target"
                else
                    echo -e "  ${RED}⚠${NC} $target -> $(readlink "$home_file")"
                fi
            elif [[ -e "$home_file" ]]; then
                echo -e "  ${RED}✗${NC} $target (not linked)"
            else
                echo -e "  ${YELLOW}○${NC} $target (missing)"
            fi
        done < <(get_targets "$pkg")
    done

    echo -e "\n${YELLOW}[manual & custom symlinks]${NC}"
    for entry in "${MANUAL_LINKS[@]}"; do
        local src="${entry%%:*}" target="${entry#*:}"
        if [[ -L "$target" ]]; then
            if [[ "$(readlink "$target")" == "$src" ]]; then
                echo -e "  ${GREEN}✓${NC} $target"
            else
                echo -e "  ${RED}⚠${NC} $target -> $(readlink "$target")"
            fi
        elif [[ -e "$target" ]]; then
            echo -e "  ${RED}✗${NC} $target (not linked)"
        else
            echo -e "  ${YELLOW}○${NC} $target (missing)"
        fi
    done

    if [[ ${#APP_COPIES[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}[app-managed copies]${NC}"
        for entry in "${APP_COPIES[@]}"; do
            app_copy_check "${entry%%:*}" "${entry#*:}"
        done
    fi

    echo -e "\n${YELLOW}[custom overlay]${NC}"
    if [[ -d "$CUSTOM_DIR" ]]; then
        echo -e "  ${GREEN}✓${NC} $CUSTOM_DIR"
    else
        echo -e "  ${YELLOW}○${NC} none (run ./dotfiles.sh init-custom to create one)"
    fi

    echo -e "\n${YELLOW}[homebrew]${NC}"
    if command -v brew &>/dev/null; then
        local total
        total=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✓${NC} $total formulae installed"
        total=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✓${NC} $total casks installed"
    else
        echo -e "  ${RED}✗${NC} Homebrew not installed"
    fi
}

# Main
case "${1:-}" in
    ansible)     shift; cmd_ansible "$@" ;;
    apply)       cmd_apply ;;
    link)        cmd_link ;;
    status)      cmd_status ;;
    diff)        cmd_diff ;;
    capture)     cmd_capture ;;
    brew)        cmd_brew ;;
    init-custom) cmd_init_custom ;;
    *)           usage ;;
esac
