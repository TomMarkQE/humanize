#!/usr/bin/env bash
# Convenience wrapper for the Codex-native Humanize installer.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec "$SCRIPT_DIR/install-codex-native.sh" "$@"
