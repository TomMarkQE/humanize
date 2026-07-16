#!/usr/bin/env bash
# Codex-native install, upgrade migration, idempotency, and uninstall tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$PROJECT_ROOT/scripts/install-skills-codex.sh"
UNINSTALL="$PROJECT_ROOT/scripts/uninstall-skills-codex.sh"
UNIFIED="$PROJECT_ROOT/scripts/install-skill.sh"
PASSED=0
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n  Expected: %s\n  Got: %s\n' "$1" "${2:-}" "${3:-}" >&2; FAILED=$((FAILED + 1)); }
assert_file() { [[ -f "$1" ]] && pass "$2" || fail "$2" "$1" "missing"; }
assert_absent() { [[ ! -e "$1" ]] && pass "$2" || fail "$2" "absent" "$1 exists"; }
assert_contains() { grep -qE "$2" "$1" && pass "$3" || fail "$3" "$2" "not found in $1"; }
assert_not_contains() { if grep -qE "$2" "$1"; then fail "$3" "pattern absent: $2" "found"; else pass "$3"; fi; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
CODEX_CONFIG="$TMP_ROOT/codex"
SKILLS="$TMP_ROOT/agent-skills"
AGENTS="$TMP_ROOT/agents"
COMMAND_BIN="$TMP_ROOT/bin"
CODEX_LOG="$TMP_ROOT/codex-invocations.log"
mkdir -p "$CODEX_CONFIG/skills/humanize" "$CODEX_CONFIG/skills/humanize-rlcr" "$COMMAND_BIN" "$TMP_ROOT/fake-bin"

cat > "$CODEX_CONFIG/hooks.json" <<EOF
{
  "description": "user hooks",
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "/user/session-start.sh"}]}],
    "Stop": [
      {"hooks": [{"type": "command", "command": "$CODEX_CONFIG/skills/humanize/hooks/loop-codex-stop-hook.sh"}]},
      {"hooks": [{"type": "command", "command": "/user/keep-stop.sh"}]}
    ]
  }
}
EOF
printf '%s\n' 'legacy humanize skill' > "$CODEX_CONFIG/skills/humanize/SKILL.md"
printf '%s\n' 'legacy rlcr skill' > "$CODEX_CONFIG/skills/humanize-rlcr/SKILL.md"
cat > "$COMMAND_BIN/bitlesson-selector" <<EOF
#!/usr/bin/env bash
# Humanize bitlesson selector runtime
exec '$CODEX_CONFIG/skills/humanize/scripts/bitlesson-select.sh' "\$@"
EOF
chmod +x "$COMMAND_BIN/bitlesson-selector"
cat > "$TMP_ROOT/fake-bin/codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$CODEX_LOG'
exit 99
EOF
chmod +x "$TMP_ROOT/fake-bin/codex"

run_install() {
    PATH="$TMP_ROOT/fake-bin:$PATH" HOME="$TMP_ROOT/home" "$INSTALL" \
        --repo-root "$PROJECT_ROOT" \
        --codex-config-dir "$CODEX_CONFIG" \
        --codex-skills-dir "$SKILLS" \
        --codex-agents-dir "$AGENTS" \
        --command-bin-dir "$COMMAND_BIN" \
        "$@"
}

run_install > "$TMP_ROOT/install.log" 2>&1

for skill in humanize humanize-rlcr humanize-consult humanize-gen-plan humanize-refine-plan; do
    assert_file "$SKILLS/$skill/SKILL.md" "native installer installs $skill"
    assert_file "$SKILLS/$skill/.humanize-native-managed" "native installer marks $skill as managed"
done

for agent in humanize-worker humanize-implementation-reviewer humanize-code-reviewer humanize-researcher; do
    assert_file "$AGENTS/$agent.toml" "native installer installs $agent custom agent"
done

assert_file "$SKILLS/humanize/scripts/native-rlcr.py" "native installer includes deterministic state runtime"
assert_file "$SKILLS/humanize/scripts/validate-gen-plan-io.sh" "native installer includes plan validator"
assert_file "$SKILLS/humanize/scripts/validate-refine-plan-io.sh" "native installer includes refine validator"
assert_absent "$SKILLS/humanize/hooks" "native installer omits legacy hook runtime"
assert_absent "$SKILLS/humanize/scripts/ask-codex.sh" "native installer omits nested one-shot model script"
assert_absent "$SKILLS/humanize/scripts/setup-rlcr-loop.sh" "native installer omits legacy loop setup script"
assert_absent "$SKILLS/humanize/scripts/bitlesson-select.sh" "native installer omits model-backed BitLesson selector"

assert_contains "$SKILLS/humanize-rlcr/SKILL.md" 'humanize_worker' "installed RLCR skill names the native worker agent"
assert_contains "$SKILLS/humanize-rlcr/SKILL.md" 'humanize_implementation_reviewer' "installed RLCR skill names the independent implementation reviewer"
assert_contains "$SKILLS/humanize-rlcr/SKILL.md" 'humanize_code_reviewer' "installed RLCR skill names the independent code reviewer"
assert_not_contains "$SKILLS/humanize-rlcr/SKILL.md" '\{\{HUMANIZE_RUNTIME_ROOT\}\}' "installed RLCR skill has a hydrated runtime path"
assert_not_contains "$SKILLS/humanize-gen-plan/SKILL.md" '^(type|user-invocable|disable-model-invocation|hide-from-slash-command-tool):' "Codex installer strips provider-specific frontmatter"

assert_absent "$CODEX_CONFIG/skills/humanize" "upgrade removes duplicate legacy humanize skill"
assert_absent "$CODEX_CONFIG/skills/humanize-rlcr" "upgrade removes duplicate legacy RLCR skill"
assert_absent "$COMMAND_BIN/bitlesson-selector" "upgrade removes legacy model-selector shim"
assert_file "$CODEX_CONFIG/humanize-native-install.json" "native installer writes an ownership manifest"

assert_contains "$CODEX_CONFIG/hooks.json" '/user/keep-stop\.sh' "migration preserves unrelated Stop hooks"
assert_contains "$CODEX_CONFIG/hooks.json" '/user/session-start\.sh' "migration preserves unrelated hook events"
assert_not_contains "$CODEX_CONFIG/hooks.json" 'loop-codex-stop-hook\.sh|pr-loop-stop-hook\.sh' "migration removes legacy Humanize model hooks"

if [[ ! -s "$CODEX_LOG" ]]; then
    pass "native installer never invokes the Codex CLI"
else
    fail "native installer never invokes the Codex CLI" "empty log" "$(cat "$CODEX_LOG")"
fi

python3 - "$CODEX_CONFIG/humanize-native-install.json" "$SKILLS" "$AGENTS" <<'PY'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["mode"] == "codex-native"
assert pathlib.Path(manifest["skills_dir"]) == pathlib.Path(sys.argv[2])
assert pathlib.Path(manifest["agents_dir"]) == pathlib.Path(sys.argv[3])
assert len(manifest["skills"]) == len(set(manifest["skills"])) == 5
assert len(manifest["agents"]) == len(set(manifest["agents"])) == 4
PY
pass "manifest records one native copy of every managed asset"

# Idempotent reinstall must not duplicate or disturb unrelated assets.
printf '%s\n' 'name = "user_agent"' > "$AGENTS/user-agent.toml"
cat > "$COMMAND_BIN/bitlesson-selector" <<EOF
#!/usr/bin/env bash
# Kimi-owned Humanize selector shim
exec '$TMP_ROOT/kimi-skills/humanize/scripts/bitlesson-select.sh' "\$@"
EOF
chmod +x "$COMMAND_BIN/bitlesson-selector"
run_install > "$TMP_ROOT/install-2.log" 2>&1
assert_file "$AGENTS/user-agent.toml" "idempotent install preserves unrelated custom agents"
assert_file "$COMMAND_BIN/bitlesson-selector" "Codex reinstall preserves a Kimi-owned selector shim"
assert_contains "$COMMAND_BIN/bitlesson-selector" 'kimi-skills/humanize/scripts/bitlesson-select\.sh' "preserved selector shim still targets Kimi runtime"
assert_contains "$CODEX_CONFIG/hooks.json" '/user/keep-stop\.sh' "idempotent install preserves unrelated hooks"
agent_count="$(find "$AGENTS" -maxdepth 1 -name 'humanize-*.toml' -type f | wc -l | tr -d ' ')"
if [[ "$agent_count" == "4" ]]; then
    pass "idempotent install leaves exactly four managed agents"
else
    fail "idempotent install leaves exactly four managed agents" "4" "$agent_count"
fi
skill_count="$(find "$SKILLS" -mindepth 1 -maxdepth 1 -name 'humanize*' -type d | wc -l | tr -d ' ')"
if [[ "$skill_count" == "5" ]]; then
    pass "idempotent install leaves exactly five managed skills"
else
    fail "idempotent install leaves exactly five managed skills" "5" "$skill_count"
fi

# The unified installer must route --target codex to the same native path.
UNIFIED_CONFIG="$TMP_ROOT/unified-codex"
UNIFIED_SKILLS="$TMP_ROOT/unified-skills"
UNIFIED_AGENTS="$TMP_ROOT/unified-agents"
PATH="$TMP_ROOT/fake-bin:$PATH" HOME="$TMP_ROOT/home" "$UNIFIED" \
    --target codex \
    --repo-root "$PROJECT_ROOT" \
    --codex-config-dir "$UNIFIED_CONFIG" \
    --codex-skills-dir "$UNIFIED_SKILLS" \
    --codex-agents-dir "$UNIFIED_AGENTS" \
    --command-bin-dir "$TMP_ROOT/unified-bin" \
    > "$TMP_ROOT/unified.log" 2>&1
assert_file "$UNIFIED_SKILLS/humanize-rlcr/SKILL.md" "unified --target codex uses native RLCR assets"
assert_file "$UNIFIED_AGENTS/humanize-worker.toml" "unified --target codex installs custom agents"
assert_absent "$UNIFIED_CONFIG/hooks.json" "unified --target codex does not create hooks.json"

# A combined install must keep provider assets separate and preserve Kimi's shim.
BOTH_ROOT="$TMP_ROOT/both"
PATH="$TMP_ROOT/fake-bin:$PATH" HOME="$TMP_ROOT/home" "$UNIFIED" \
    --target both \
    --repo-root "$PROJECT_ROOT" \
    --kimi-skills-dir "$BOTH_ROOT/kimi-skills" \
    --codex-skills-dir "$BOTH_ROOT/codex-skills" \
    --codex-config-dir "$BOTH_ROOT/codex" \
    --codex-agents-dir "$BOTH_ROOT/codex-agents" \
    --command-bin-dir "$BOTH_ROOT/bin" \
    > "$TMP_ROOT/both.log" 2>&1
assert_file "$BOTH_ROOT/kimi-skills/humanize-rlcr/SKILL.md" "combined install keeps legacy Kimi RLCR assets"
assert_file "$BOTH_ROOT/codex-skills/humanize-rlcr/SKILL.md" "combined install keeps native Codex RLCR assets"
assert_contains "$BOTH_ROOT/kimi-skills/humanize-rlcr/SKILL.md" 'setup-rlcr-loop\.sh' "combined install keeps the unchanged Kimi RLCR workflow"
assert_contains "$BOTH_ROOT/codex-skills/humanize-rlcr/SKILL.md" 'Codex-native workflow' "combined install gives Codex the native coordinator skill"
assert_file "$BOTH_ROOT/bin/bitlesson-selector" "combined install preserves Kimi selector shim"
assert_contains "$BOTH_ROOT/bin/bitlesson-selector" 'kimi-skills/humanize/scripts/bitlesson-select\.sh' "combined selector shim still targets Kimi"

set +e
PATH="$TMP_ROOT/fake-bin:$PATH" HOME="$TMP_ROOT/home" "$UNIFIED" \
    --target both --repo-root "$PROJECT_ROOT" --skills-dir "$BOTH_ROOT/shared" \
    > "$TMP_ROOT/both-conflict.log" 2>&1
both_conflict_exit=$?
set -e
if [[ "$both_conflict_exit" -ne 0 ]]; then
    pass "combined install rejects a shared provider skill directory"
else
    fail "combined install rejects a shared provider skill directory" "non-zero" "0"
fi
assert_contains "$TMP_ROOT/both-conflict.log" 'separate --kimi-skills-dir and --codex-skills-dir' "combined path conflict explains the migration"

# Dry run must not create targets.
DRY_ROOT="$TMP_ROOT/dry"
PATH="$TMP_ROOT/fake-bin:$PATH" HOME="$TMP_ROOT/home" "$INSTALL" \
    --repo-root "$PROJECT_ROOT" \
    --codex-config-dir "$DRY_ROOT/codex" \
    --codex-skills-dir "$DRY_ROOT/skills" \
    --codex-agents-dir "$DRY_ROOT/agents" \
    --command-bin-dir "$DRY_ROOT/bin" \
    --dry-run > "$TMP_ROOT/dry.log" 2>&1
assert_absent "$DRY_ROOT/skills" "dry-run creates no skill assets"
assert_absent "$DRY_ROOT/agents" "dry-run creates no agent assets"

# Malformed hooks must fail closed rather than overwriting user configuration.
MALFORMED="$TMP_ROOT/malformed"
mkdir -p "$MALFORMED"
printf '{not-json\n' > "$MALFORMED/hooks.json"
set +e
PATH="$TMP_ROOT/fake-bin:$PATH" HOME="$TMP_ROOT/home" "$INSTALL" \
    --repo-root "$PROJECT_ROOT" \
    --codex-config-dir "$MALFORMED" \
    --codex-skills-dir "$TMP_ROOT/malformed-skills" \
    --codex-agents-dir "$TMP_ROOT/malformed-agents" \
    --command-bin-dir "$TMP_ROOT/malformed-bin" \
    > "$TMP_ROOT/malformed.log" 2>&1
malformed_exit=$?
set -e
if [[ "$malformed_exit" -ne 0 ]]; then
    pass "malformed existing hooks fail the migration safely"
else
    fail "malformed existing hooks fail the migration safely" "non-zero" "0"
fi
assert_contains "$MALFORMED/hooks.json" '^\{not-json$' "failed migration leaves malformed user file untouched"

# Uninstall removes only managed assets and keeps user-owned files/hooks.
HOME="$TMP_ROOT/home" "$UNINSTALL" --codex-config-dir "$CODEX_CONFIG" > "$TMP_ROOT/uninstall.log" 2>&1
for skill in humanize humanize-rlcr humanize-consult humanize-gen-plan humanize-refine-plan; do
    assert_absent "$SKILLS/$skill" "uninstall removes managed $skill"
done
for agent in humanize-worker humanize-implementation-reviewer humanize-code-reviewer humanize-researcher; do
    assert_absent "$AGENTS/$agent.toml" "uninstall removes managed $agent agent"
done
assert_file "$AGENTS/user-agent.toml" "uninstall preserves unrelated custom agents"
assert_file "$COMMAND_BIN/bitlesson-selector" "Codex uninstall preserves a Kimi-owned selector shim"
assert_contains "$CODEX_CONFIG/hooks.json" '/user/keep-stop\.sh' "uninstall preserves unrelated Stop hook"
assert_absent "$CODEX_CONFIG/humanize-native-install.json" "uninstall removes ownership manifest"

printf '\nPassed: %d\nFailed: %d\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
