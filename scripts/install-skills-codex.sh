#!/usr/bin/env bash
# Convenience wrapper: install Humanize's provider-specific native Codex skills.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
"$SCRIPT_DIR/install-skill.sh" --target codex "$@"
