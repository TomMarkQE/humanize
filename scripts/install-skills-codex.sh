#!/usr/bin/env bash
# Convenience wrapper for the Codex-only Codex Humanizer installer.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
"$SCRIPT_DIR/install-codex-humanizer.sh" "$@"
