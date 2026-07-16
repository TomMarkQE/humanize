#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
RUNTIME="$ROOT/scripts/native-rlcr.py"
PASSED=0
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s (expected=%s actual=%s)\n' "$1" "${2:-}" "${3:-}" >&2; FAILED=$((FAILED + 1)); }
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2].split("."):
    value = value.get(key) if isinstance(value, dict) else None
if isinstance(value, bool):
    print(str(value).lower())
elif value is not None:
    print(value)
PY
}
run_capture() {
  local out="$1"; shift
  set +e
  "$@" >"$out" 2>&1
  CAPTURE_EXIT=$?
  set -e
}
write_summary() {
  local path="$1" round="$2"
  cat > "$path" <<EOF
# Humanize Round $round Summary

## Work Completed
- Completed the bounded objective for this test round.

## Files Changed
- app.txt

## Validation
- Deterministic fixture validation passed.

## Remaining Items
- None.
EOF
}

[[ -f "$RUNTIME" ]] && pass 'native runtime exists' || fail 'native runtime exists' "$RUNTIME" missing
python3 -m py_compile "$RUNTIME" && pass 'native runtime compiles' || fail 'native runtime compiles' success failure
if grep -Eq 'subprocess\.(run|Popen).*codex|["'"']codex["'"'][[:space:]]*,[[:space:]]*["'"'](exec|review)' "$RUNTIME"; then
  fail 'runtime performs no model CLI call' none match
else
  pass 'runtime performs no model CLI call'
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name 'Humanize Test'
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config commit.gpgsign false
cat > "$REPO/.gitignore" <<'EOF'
.humanize/
EOF
cat > "$REPO/plan.md" <<'EOF'
# Native RLCR Fixture

Implement the bounded behavior.

## Acceptance Criteria
- AC-1: The state machine reaches independent review and completion.
EOF
printf 'initial\n' > "$REPO/app.txt"
git -C "$REPO" add .gitignore plan.md app.txt
git -C "$REPO" commit -q -m initial

INIT="$TMP/init.json"
run_capture "$INIT" python3 "$RUNTIME" init --project-root "$REPO" --plan-file plan.md --track-plan-file --max-rounds 5 --loop-dir "$REPO/.humanize/rlcr/native-test"
assert_eq 'init succeeds' 0 "$CAPTURE_EXIT"
assert_eq 'init delegates worker' delegate_worker "$(json_get "$INIT" next_action)"
LOOP="$(json_get "$INIT" loop_dir)"
STATE="$LOOP/state.json"
assert_eq 'state engine is native' codex-native "$(json_get "$STATE" engine)"
assert_eq 'initial phase is implementation' implementation "$(json_get "$STATE" phase)"

write_summary "$LOOP/round-0-summary.md" 0
printf 'round0\n' >> "$REPO/app.txt"
run_capture "$TMP/dirty.json" python3 "$RUNTIME" checkpoint --loop-dir "$LOOP"
if [[ "$CAPTURE_EXIT" -ne 0 ]]; then pass 'checkpoint rejects dirty worker tree'; else fail 'checkpoint rejects dirty worker tree' nonzero 0; fi
assert_eq 'dirty checkpoint error is explicit' working_tree_dirty "$(json_get "$TMP/dirty.json" error.code)"

git -C "$REPO" add app.txt
git -C "$REPO" commit -q -m round0
run_capture "$TMP/checkpoint0.json" python3 "$RUNTIME" checkpoint --loop-dir "$LOOP" --summary-file "$LOOP/round-0-summary.md"
assert_eq 'checkpoint succeeds' 0 "$CAPTURE_EXIT"
assert_eq 'checkpoint delegates implementation reviewer' delegate_implementation_reviewer "$(json_get "$TMP/checkpoint0.json" next_action)"

cat > "$LOOP/bad-impl.md" <<'EOF'
This result omits stable markers.
EOF
run_capture "$TMP/bad-impl.json" python3 "$RUNTIME" record-review --loop-dir "$LOOP" --kind implementation --review-file "$LOOP/bad-impl.md"
if [[ "$CAPTURE_EXIT" -ne 0 ]]; then pass 'malformed implementation review fails closed'; else fail 'malformed implementation review fails closed' nonzero 0; fi
assert_eq 'malformed review reports contract error' review_contract_invalid "$(json_get "$TMP/bad-impl.json" error.code)"

cat > "$LOOP/impl0.md" <<'EOF'
HUMANIZE_IMPLEMENTATION_REVIEW: continue
MAINLINE_PROGRESS: advanced
One acceptance condition still needs evidence.
EOF
run_capture "$TMP/continue.json" python3 "$RUNTIME" record-review --loop-dir "$LOOP" --kind implementation --review-file "$LOOP/impl0.md"
assert_eq 'continue review succeeds' 0 "$CAPTURE_EXIT"
assert_eq 'continue opens next worker round' delegate_worker "$(json_get "$TMP/continue.json" next_action)"
assert_eq 'continue advances round' 1 "$(json_get "$TMP/continue.json" round)"

printf 'round1\n' >> "$REPO/app.txt"
git -C "$REPO" add app.txt
git -C "$REPO" commit -q -m round1
write_summary "$LOOP/round-1-summary.md" 1
run_capture "$TMP/checkpoint1.json" python3 "$RUNTIME" checkpoint --loop-dir "$LOOP"
assert_eq 'second checkpoint succeeds' 0 "$CAPTURE_EXIT"

cat > "$LOOP/contradictory.md" <<'EOF'
HUMANIZE_IMPLEMENTATION_REVIEW: complete
MAINLINE_PROGRESS: stalled
Contradictory completion.
EOF
run_capture "$TMP/contradictory.json" python3 "$RUNTIME" record-review --loop-dir "$LOOP" --kind implementation --review-file "$LOOP/contradictory.md"
if [[ "$CAPTURE_EXIT" -ne 0 ]]; then pass 'contradictory completion fails closed'; else fail 'contradictory completion fails closed' nonzero 0; fi
assert_eq 'contradiction is a contract error' review_contract_invalid "$(json_get "$TMP/contradictory.json" error.code)"

cat > "$LOOP/impl1.md" <<'EOF'
HUMANIZE_IMPLEMENTATION_REVIEW: complete
MAINLINE_PROGRESS: advanced
All acceptance criteria have implementation and test evidence.
EOF
run_capture "$TMP/impl-complete.json" python3 "$RUNTIME" record-review --loop-dir "$LOOP" --kind implementation --review-file "$LOOP/impl1.md"
assert_eq 'implementation completion succeeds' 0 "$CAPTURE_EXIT"
assert_eq 'implementation completion delegates code reviewer' delegate_code_reviewer "$(json_get "$TMP/impl-complete.json" next_action)"

cat > "$LOOP/code-invalid.md" <<'EOF'
HUMANIZE_CODE_REVIEW: changes_required
Finding without priority marker.
EOF
run_capture "$TMP/code-invalid.json" python3 "$RUNTIME" record-review --loop-dir "$LOOP" --kind code --review-file "$LOOP/code-invalid.md"
if [[ "$CAPTURE_EXIT" -ne 0 ]]; then pass 'code findings require priority marker'; else fail 'code findings require priority marker' nonzero 0; fi
assert_eq 'invalid code review is contract error' review_contract_invalid "$(json_get "$TMP/code-invalid.json" error.code)"

cat > "$LOOP/code-pass.md" <<'EOF'
HUMANIZE_CODE_REVIEW: pass
The branch diff and validation evidence contain no blocking defect.
EOF
run_capture "$TMP/pass.json" python3 "$RUNTIME" record-review --loop-dir "$LOOP" --kind code --review-file "$LOOP/code-pass.md"
assert_eq 'code review pass succeeds' 0 "$CAPTURE_EXIT"
assert_eq 'code review pass reports completion' report_complete "$(json_get "$TMP/pass.json" next_action)"
assert_eq 'state becomes complete' complete "$(json_get "$STATE" status)"

run_capture "$TMP/fail-terminal.json" python3 "$RUNTIME" fail --loop-dir "$LOOP" --code agent_failed --message later
if [[ "$CAPTURE_EXIT" -ne 0 ]]; then pass 'terminal loop cannot be failed again'; else fail 'terminal loop cannot be failed again' nonzero 0; fi
assert_eq 'terminal mutation is explicit' loop_terminal "$(json_get "$TMP/fail-terminal.json" error.code)"

printf '\nPassed: %d\nFailed: %d\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
