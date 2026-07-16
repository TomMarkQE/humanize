#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
RUNNER="$ROOT/tests/run-all-tests.py"
PASSED=0
FAILED=0
TMP_SUITE="$ROOT/tests/.runner-fixture-$$.sh"
TMP_TIMEOUT="$ROOT/tests/.runner-timeout-$$.sh"
trap 'rm -f "$TMP_SUITE" "$TMP_TIMEOUT"' EXIT

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

if python3 -m py_compile "$RUNNER"; then pass 'Python test runner compiles'; else fail 'Python test runner compiles'; fi

set +e
python3 "$RUNNER" --jobs 1 does-not-exist.sh >/tmp/humanize-runner-missing-$$.log 2>&1
code=$?
set -e
if [[ "$code" -ne 0 ]]; then pass 'missing listed suite fails closed'; else fail 'missing listed suite fails closed'; fi
rm -f /tmp/humanize-runner-missing-$$.log

set +e
python3 "$RUNNER" --jobs 1 test-codex-native-runtime.sh test-codex-native-runtime.sh >/tmp/humanize-runner-duplicate-$$.log 2>&1
code=$?
set -e
if [[ "$code" -ne 0 ]]; then pass 'duplicate suite manifest fails closed'; else fail 'duplicate suite manifest fails closed'; fi
rm -f /tmp/humanize-runner-duplicate-$$.log

cat > "$TMP_SUITE" <<'EOF'
#!/usr/bin/env bash
printf 'Passed: 1\nFailed: 1\n'
exit 0
EOF
chmod +x "$TMP_SUITE"
set +e
python3 "$RUNNER" --jobs 1 "$(basename "$TMP_SUITE")" >/tmp/humanize-runner-reported-failure-$$.log 2>&1
code=$?
set -e
if [[ "$code" -ne 0 ]]; then pass 'reported failed assertions override zero suite exit'; else fail 'reported failed assertions override zero suite exit'; fi
rm -f /tmp/humanize-runner-reported-failure-$$.log

cat > "$TMP_TIMEOUT" <<'EOF'
#!/usr/bin/env bash
sleep 3
printf 'Passed: 1\nFailed: 0\n'
EOF
chmod +x "$TMP_TIMEOUT"
set +e
python3 "$RUNNER" --jobs 1 --timeout 1 "$(basename "$TMP_TIMEOUT")" >/tmp/humanize-runner-timeout-$$.log 2>&1
code=$?
set -e
if [[ "$code" -ne 0 ]]; then pass 'suite timeout fails closed'; else fail 'suite timeout fails closed'; fi
rm -f /tmp/humanize-runner-timeout-$$.log

if python3 "$RUNNER" --jobs 1 --timeout 120 test-codex-native-runtime.sh >/tmp/humanize-runner-success-$$.log 2>&1; then
  pass 'selected passing suite succeeds through runner'
else
  fail 'selected passing suite succeeds through runner'
fi
rm -f /tmp/humanize-runner-success-$$.log

printf '\nPassed: %d\nFailed: %d\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
