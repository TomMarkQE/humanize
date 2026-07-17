#!/usr/bin/env bash
# Codex Humanizer install, migration, and native contract tests.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/test-helpers.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/test-helpers.sh"
else
  TESTS_PASSED=0; TESTS_FAILED=0
  pass(){ echo "PASS: $1"; TESTS_PASSED=$((TESTS_PASSED+1)); }
  fail(){ echo "FAIL: $1" >&2; TESTS_FAILED=$((TESTS_FAILED+1)); }
  print_test_summary(){ echo "Passed: $TESTS_PASSED"; echo "Failed: $TESTS_FAILED"; [[ $TESTS_FAILED -eq 0 ]]; }
fi

INSTALL="$PROJECT_ROOT/scripts/install-skills-codex.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILLS="$TMP/codex/skills"
CONFIG="$TMP/codex"
BIN="$TMP/bin"
mkdir -p "$SKILLS/humanize/scripts" "$CONFIG" "$BIN"

cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
echo invoked >> "${CODEX_INVOCATION_LOG:?}"
exit 99
SH
chmod +x "$BIN/codex"
INVOCATIONS="$TMP/codex.log"

printf '%s\n' '# Humanize for Codex' 'spawn_agent native_subagents' > "$SKILLS/humanize/SKILL.md"
printf '%s\n' '#!/usr/bin/env python3' > "$SKILLS/humanize/scripts/native-rlcr.py"
for name in humanize-gen-plan humanize-refine-plan humanize-rlcr; do
  mkdir -p "$SKILLS/$name"
  printf 'legacy native skill\n' > "$SKILLS/$name/SKILL.md"
done

cat > "$CONFIG/hooks.json" <<'JSON'
{
  "hooks": {
    "Stop": [{"hooks": [
      {"type": "command", "command": "/old/humanize/hooks/loop-codex-stop-hook.sh"},
      {"type": "command", "command": "/custom/keep.sh"}
    ]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "/custom/start.sh"}]}]
  }
}
JSON

if PATH="$BIN:$PATH" CODEX_INVOCATION_LOG="$INVOCATIONS" \
  bash "$INSTALL" --repo-root "$PROJECT_ROOT" --codex-skills-dir "$SKILLS" --codex-config-dir "$CONFIG" \
  >"$TMP/install.log" 2>&1; then
  pass "Codex-only installer succeeds"
else
  fail "Codex-only installer succeeds"
  cat "$TMP/install.log" >&2
fi

for name in codex-humanizer codex-humanizer-gen-plan codex-humanizer-refine-plan codex-humanizer-rlcr; do
  [[ -f "$SKILLS/$name/SKILL.md" ]] && pass "installs $name" || fail "installs $name"
done
for name in humanize humanize-gen-plan humanize-refine-plan humanize-rlcr; do
  [[ ! -e "$SKILLS/$name" ]] && pass "migrates old native $name" || fail "migrates old native $name"
done

[[ -x "$SKILLS/codex-humanizer/scripts/native-rlcr.py" ]] && pass "installs executable RLCR runtime" || fail "installs executable RLCR runtime"
[[ -x "$SKILLS/codex-humanizer/scripts/codex-humanizer-plan-io.py" ]] && pass "installs executable plan validator" || fail "installs executable plan validator"
if grep -R '{{HUMANIZE_RUNTIME_ROOT}}' "$SKILLS"/codex-humanizer*/SKILL.md >/dev/null; then
  fail "hydrates installed Skill runtime paths"
else
  pass "hydrates installed Skill runtime paths"
fi
[[ ! -s "$INVOCATIONS" ]] && pass "installer never invokes Codex CLI" || fail "installer never invokes Codex CLI"

HOOK_CHECK="$(python3 - "$CONFIG/hooks.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
cmds=[h.get('command','') for g in j.get('hooks',{}).get('Stop',[]) for h in g.get('hooks',[]) if isinstance(h,dict)]
print('managed=' + str(any('loop-codex-stop-hook.sh' in x for x in cmds)).lower())
print('keep=' + str('/custom/keep.sh' in cmds).lower())
print('session=' + str(j['hooks']['SessionStart'][0]['hooks'][0]['command']=='/custom/start.sh').lower())
PY
)"
grep -q '^managed=false$' <<<"$HOOK_CHECK" && pass "removes stale managed Stop hook" || fail "removes stale managed Stop hook"
grep -q '^keep=true$' <<<"$HOOK_CHECK" && pass "preserves unrelated Stop hook" || fail "preserves unrelated Stop hook"
grep -q '^session=true$' <<<"$HOOK_CHECK" && pass "preserves unrelated hook groups" || fail "preserves unrelated hook groups"

if bash "$INSTALL" --repo-root "$PROJECT_ROOT" --codex-skills-dir "$SKILLS" --codex-config-dir "$CONFIG" >"$TMP/reinstall.log" 2>&1; then
  pass "installer is idempotent"
else
  fail "installer is idempotent"
fi
if bash "$INSTALL" --target kimi --repo-root "$PROJECT_ROOT" --codex-skills-dir "$SKILLS" >"$TMP/unsupported.log" 2>&1; then
  fail "rejects non-Codex targets"
else
  pass "rejects non-Codex targets"
fi

for test_file in test-native-subagent-skills.py test-native-rlcr.py test-codex-humanizer-plan-io.py; do
  if python3 "$SCRIPT_DIR/$test_file" >"$TMP/$test_file.log" 2>&1; then
    pass "$test_file passes"
  else
    fail "$test_file passes"
    cat "$TMP/$test_file.log" >&2
  fi
done

print_test_summary "Codex Humanizer Install Tests"
