#!/usr/bin/env bash
# vm_test.sh — Headless end-to-end repeatability test in a disposable Tart macOS VM.
#
# Clones a clean macOS base image, copies the public groundhog repo (excluding
# custom/ and local build state) into ~/groundhog inside the VM, runs:
#   1. Fresh bootstrap (ansible/bootstrap.sh)
#   2. Second Ansible pass (idempotency check)
#   3. In-VM verification (./groundhog status + make verify)
# and deletes the disposable VM on exit (unless --keep is passed).
#
# Requirements:
#   brew tap openai/tools && brew install openai/tools/tart
#
# Usage:
#   scripts/vm_test.sh                           # Full fresh-Mac test
#   scripts/vm_test.sh --tags "dev-tools,dotfiles"  # Fast subset smoke test
#   scripts/vm_test.sh --image groundhog-base    # Use a pre-prepped local Tart snapshot
#   scripts/vm_test.sh --keep                    # Keep VM after completion for debugging

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_IMAGE="${GROUNDHOG_VM_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
VM_NAME="groundhog-test-$$"
VM_CPUS="${GROUNDHOG_VM_CPUS:-4}"
VM_MEM="${GROUNDHOG_VM_MEM:-8192}"
VM_TAGS="${VM_TAGS:-}"
KEEP_VM=false
VM_PID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      BASE_IMAGE="$2"
      shift 2
      ;;
    --tags)
      VM_TAGS="$2"
      shift 2
      ;;
    --keep)
      KEEP_VM=true
      shift
      ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v tart >/dev/null 2>&1; then
  echo "Error: tart is not installed. Install with: brew tap openai/tools && brew install openai/tools/tart" >&2
  exit 1
fi

cleanup() {
  local rc=$?
  if [[ "$KEEP_VM" == "true" ]]; then
    echo
    echo "==> Keeping VM '$VM_NAME' (--keep). Inspect with: tart exec $VM_NAME zsh"
    echo "    Delete later with: tart stop $VM_NAME && tart delete $VM_NAME"
    return "$rc"
  fi
  echo
  echo "==> Cleaning up disposable VM '$VM_NAME'..."
  tart stop "$VM_NAME" >/dev/null 2>&1 || true
  if [[ -n "$VM_PID" ]]; then
    wait "$VM_PID" 2>/dev/null || true
  fi
  tart delete "$VM_NAME" >/dev/null 2>&1 || true
  return "$rc"
}
trap cleanup EXIT INT TERM

echo "==> Cloning Tart VM '$VM_NAME' from '$BASE_IMAGE'..."
tart clone "$BASE_IMAGE" "$VM_NAME"
tart set "$VM_NAME" --cpu "$VM_CPUS" --memory "$VM_MEM"

echo "==> Booting VM headless (mounting repo read-only)..."
tart run --no-graphics --dir="repo:${REPO_DIR}:ro" "$VM_NAME" >/tmp/"${VM_NAME}".log 2>&1 &
VM_PID=$!

echo "==> Waiting for Tart guest agent..."
ready=false
for _ in $(seq 1 90); do
  if tart exec "$VM_NAME" true >/dev/null 2>&1; then
    ready=true
    break
  fi
  if ! kill -0 "$VM_PID" 2>/dev/null; then
    echo "Error: Tart VM exited early. Log:" >&2
    cat /tmp/"${VM_NAME}".log >&2
    exit 1
  fi
  sleep 2
done

if [[ "$ready" != "true" ]]; then
  echo "Error: Timed out waiting for Tart guest agent." >&2
  exit 1
fi

echo "==> Copying clean public groundhog repo into VM (~/groundhog)..."
tart exec "$VM_NAME" bash -euo pipefail -c '
  rm -rf "$HOME/groundhog"
  mkdir -p "$HOME/groundhog"
  rsync -a \
    --exclude=".git" \
    --exclude="custom" \
    --exclude=".venv" \
    --exclude=".pytest_cache" \
    --exclude=".ruff_cache" \
    --exclude="__pycache__" \
    --exclude=".claude" \
    "/Volumes/My Shared Files/repo/" "$HOME/groundhog/"
  git -C "$HOME/groundhog" init -b main >/dev/null
  git -C "$HOME/groundhog" config user.name "Groundhog VM"
  git -C "$HOME/groundhog" config user.email "vm@groundhog.local"
  git -C "$HOME/groundhog" add -A
  git -C "$HOME/groundhog" commit --no-gpg-sign -q -m "VM test snapshot"
'

TAG_ARGS=()
if [[ -n "$VM_TAGS" ]]; then
  TAG_ARGS=(--tags "$VM_TAGS")
fi

echo
echo "==> Pass 1: Fresh bootstrap inside VM..."
tart exec "$VM_NAME" bash -euo pipefail -c '
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
  cd "$HOME/groundhog"
  bash ansible/bootstrap.sh "$@"
' _ "${TAG_ARGS[@]}"

echo
echo "==> Pass 2: Idempotency check (second Ansible run)..."
tart exec "$VM_NAME" bash -euo pipefail -c '
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
  cd "$HOME/groundhog"
  ./groundhog ansible "$@"
' _ "${TAG_ARGS[@]}"

echo
echo "==> Pass 3: In-VM status & verification..."
ALLOW_SKIP_VAL=0
if [[ -n "$VM_TAGS" ]]; then
  ALLOW_SKIP_VAL=1
fi
tart exec "$VM_NAME" bash -euo pipefail -c '
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
  cd "$HOME/groundhog"
  ./groundhog status
  ALLOW_SKIP="$1" make verify
' _ "$ALLOW_SKIP_VAL"

echo
echo "==> Tart VM end-to-end test passed!"
