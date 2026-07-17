#!/usr/bin/env bash
# Run the maintained Codex Humanizer regression suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

printf '%s\n' '========================================'
printf '%s\n' 'Running Codex Humanizer Tests'
printf '%s\n' '========================================'
printf '\n'

python3 -m py_compile \
  "$PROJECT_ROOT/scripts/native-rlcr.py" \
  "$PROJECT_ROOT/scripts/native_rlcr_common.py" \
  "$PROJECT_ROOT/scripts/native_rlcr_state.py" \
  "$PROJECT_ROOT/scripts/native_rlcr_run.py" \
  "$PROJECT_ROOT/scripts/native_rlcr_review.py" \
  "$PROJECT_ROOT/scripts/native_rlcr_runtime.py" \
  "$PROJECT_ROOT/scripts/codex-humanizer-plan-io.py"

bash -n \
  "$PROJECT_ROOT/scripts/install-codex-humanizer.sh" \
  "$PROJECT_ROOT/scripts/install-skills-codex.sh" \
  "$PROJECT_ROOT/scripts/remove-codex-hooks.sh" \
  "$SCRIPT_DIR/test-codex-hook-install.sh"

python3 "$SCRIPT_DIR/test-native-subagent-skills.py"
python3 "$SCRIPT_DIR/test-native-rlcr.py"
python3 "$SCRIPT_DIR/test-codex-humanizer-plan-io.py"
bash "$SCRIPT_DIR/test-codex-hook-install.sh"

printf '\nAll maintained Codex Humanizer tests passed.\n'
