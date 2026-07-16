#!/usr/bin/env bash
# Portable wrapper; all scheduling and error propagation live in Python.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec python3 "$SCRIPT_DIR/run-all-tests.py" "$@"
