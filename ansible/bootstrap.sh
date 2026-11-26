#!/usr/bin/env bash
# bootstrap.sh — Run once on a fresh Mac.
#
# This is the single entry point for a new machine. It:
#   1. Installs Xcode CLT + Homebrew
#   2. Installs stow, Ansible + Galaxy collections
#   3. Runs the ansible playbook (packages, macOS defaults, dock, dev tools, dotfiles)
#      Automatically picks up custom/ (private overlay) when present.
#
# Usage:
#   cd ~/Code/utilities/groundhog && bash ansible/bootstrap.sh
#   bash ansible/bootstrap.sh --tags "homebrew,defaults,dotfiles"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

echo "==> Ensuring Homebrew..."
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
  -p "$HOME/.ansible/collections" --upgrade

echo "==> Running playbook..."
echo "    Repo dir: $DOTFILES_DIR"
echo "    Machine:  $(hostname)"
if [[ -d "${DOTFILES_DIR}/custom" ]]; then
  echo "    Overlay:  ${DOTFILES_DIR}/custom (detected)"
else
  echo "    Overlay:  none (run ./dotfiles.sh init-custom to create a private overlay)"
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

bash "${DOTFILES_DIR}/dotfiles.sh" ansible "$@"

echo
echo "==> Done. Log out and back in for all macOS defaults to take effect."
echo "    Then open a new Ghostty window (or run: exec nu)."
