#!/usr/bin/env bash
# Deprecated compatibility entrypoint. Codex-native Humanize does not install model hooks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
printf '%s\n' 'Humanize no longer installs a Codex Stop hook. Removing legacy managed hooks instead.' >&2
exec "$SCRIPT_DIR/remove-codex-hooks.sh" "$@"
