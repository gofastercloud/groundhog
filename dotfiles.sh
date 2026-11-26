#!/usr/bin/env bash
# Backwards-compatibility shim — delegates to the Python CLI/TUI (`./groundhog`).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$REPO_DIR/groundhog" "$@"
