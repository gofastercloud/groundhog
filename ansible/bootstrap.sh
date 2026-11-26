#!/usr/bin/env bash
# bootstrap.sh — Run once on a fresh Mac.
#
# Single entry point for a new machine. It:
#   1. Optionally clones your private overlay (--custom-repo <git-url>) into custom/
#   2. Installs Xcode CLT + Homebrew (from a pinned installer commit)
#   3. Installs stow, Ansible + pinned Galaxy collections
#   4. Runs the playbook via `./groundhog ansible` (packages, defaults, dock, dev tools, dotfiles)
#
# Usage:
#   cd ~/groundhog && bash ansible/bootstrap.sh
#   bash ansible/bootstrap.sh --custom-repo git@github.com:you/groundhog-private.git
#   bash ansible/bootstrap.sh --tags "homebrew,defaults,dotfiles"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOMEBREW_INSTALL_COMMIT="870ddff5dbe61d293a8b4a763090d125e59048a1"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/${HOMEBREW_INSTALL_COMMIT}/install.sh"

CUSTOM_REPO=""
ANSIBLE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --custom-repo)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Error: --custom-repo requires a Git URL argument." >&2
        exit 1
      fi
      CUSTOM_REPO="$2"
      shift 2
      ;;
    --custom-repo=*)
      CUSTOM_REPO="${1#*=}"
      shift
      ;;
    *)
      ANSIBLE_ARGS+=("$1")
      shift
      ;;
  esac
done

echo "==> Ensuring Xcode CLT..."
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install
  echo "    Complete the Xcode Command Line Tools installer dialog, then press Enter..."
  read -r
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are not installed yet. Re-run this script once installation finishes." >&2
    exit 1
  fi
fi

if [[ -n "$CUSTOM_REPO" ]]; then
  if [[ -d "${DOTFILES_DIR}/custom/.git" ]]; then
    echo "==> Private overlay already cloned at ${DOTFILES_DIR}/custom (skipping clone)."
  elif [[ -e "${DOTFILES_DIR}/custom" ]]; then
    echo "Error: ${DOTFILES_DIR}/custom exists and is not a git repo." >&2
    exit 1
  else
    echo "==> Cloning private overlay into ${DOTFILES_DIR}/custom..."
    git clone "$CUSTOM_REPO" "${DOTFILES_DIR}/custom"
  fi
fi

echo "==> Ensuring Homebrew..."
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")"
fi

BREW_BIN="$(command -v brew || true)"
if [[ -z "$BREW_BIN" ]]; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      BREW_BIN="$candidate"
      break
    fi
  done
fi
if [[ -z "$BREW_BIN" ]]; then
  echo "Homebrew installation did not provide a usable brew executable." >&2
  exit 1
fi
eval "$("$BREW_BIN" shellenv)"

echo "==> Ensuring stow is available..."
if ! command -v stow >/dev/null 2>&1; then
  brew install stow
fi

echo "==> Installing Ansible..."
if ! command -v ansible-playbook >/dev/null 2>&1; then
  brew install ansible
fi

echo "==> Installing Ansible Galaxy requirements..."
ansible-galaxy collection install -r "${SCRIPT_DIR}/requirements.yml" \
  -p "$HOME/.ansible/collections"

echo "==> Running playbook..."
echo "    Repo dir: $DOTFILES_DIR"
echo "    Machine:  $(hostname)"
if [[ -d "${DOTFILES_DIR}/custom" ]]; then
  echo "    Overlay:  ${DOTFILES_DIR}/custom (detected)"
else
  echo "    Overlay:  none (run ./groundhog init-custom to create a private overlay)"
fi

# YubiKey smart card (PIV) and pam_u2f both break Ansible's non-interactive sudo.
if ioreg -p IOUSB -l 2>/dev/null | grep -qi "YubiKey"; then
  echo
  echo "    ⚠  YubiKey detected. Please UNPLUG it before running the playbook."
  echo "       The smart card PAM module blocks non-interactive sudo."
  echo "       Plug it back in after the playbook finishes."
  echo
  read -rp "    Press Enter after removing the YubiKey (or Ctrl-C to cancel)..."
  if ioreg -p IOUSB -l 2>/dev/null | grep -qi "YubiKey"; then
    echo "    ⚠  YubiKey still detected. Continuing anyway..."
  fi
fi

"${DOTFILES_DIR}/groundhog" ansible "${ANSIBLE_ARGS[@]}"

echo
echo "==> Done. Log out and back in for all macOS defaults to take effect."
echo "    Then open a new Ghostty window (or run: exec nu)."
