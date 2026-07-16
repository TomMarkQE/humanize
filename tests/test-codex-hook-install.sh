#!/usr/bin/env bash
# Tests for provider-specific native Codex installation and legacy hook cleanup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

INSTALL_SCRIPT="$PROJECT_ROOT/scripts/install-skill.sh"

echo "=========================================="
echo "Codex Native Install Tests"
echo "=========================================="
echo ""

[[ -x "$INSTALL_SCRIPT" ]] || { echo "FATAL: install-skill.sh is not executable" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 is required" >&2; exit 1; }

setup_test_dir
FAKE_BIN="$TEST_DIR/bin"
CODEX_HOME_DIR="$TEST_DIR/codex-home"
CODEX_SKILLS_DIR="$CODEX_HOME_DIR/skills"
HOOKS_FILE="$CODEX_HOME_DIR/hooks.json"
FEATURE_LOG="$TEST_DIR/codex-invocations.log"
XDG_CONFIG_HOME_DIR="$TEST_DIR/xdg-config"
COMMAND_BIN_DIR="$TEST_DIR/command-bin"
mkdir -p "$FAKE_BIN" "$CODEX_HOME_DIR" "$COMMAND_BIN_DIR"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TEST_CODEX_INVOCATION_LOG:?}"
exit 91
EOF
chmod +x "$FAKE_BIN/codex"

cat > "$HOOKS_FILE" <<'EOF'
{
  "description": "Existing hooks",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/custom/session-start.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/old/skills/humanize/hooks/loop-codex-stop-hook.sh",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "/custom/keep-me.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF

PATH="$FAKE_BIN:$PATH" \
TEST_CODEX_INVOCATION_LOG="$FEATURE_LOG" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$CODEX_HOME_DIR" \
    --codex-skills-dir "$CODEX_SKILLS_DIR" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install.log" 2>&1

for skill in humanize humanize-gen-plan humanize-refine-plan humanize-rlcr; do
    if [[ -f "$CODEX_SKILLS_DIR/$skill/SKILL.md" ]]; then
        pass "Codex install syncs provider-specific $skill skill"
    else
        fail "Codex install syncs provider-specific $skill skill" "$CODEX_SKILLS_DIR/$skill/SKILL.md" "missing"
    fi
done

if grep -q "Humanize Native RLCR Coordinator" "$CODEX_SKILLS_DIR/humanize-rlcr/SKILL.md"; then
    pass "Codex install selects the native coordinator skill"
else
    fail "Codex install selects the native coordinator skill"
fi

if [[ -f "$CODEX_SKILLS_DIR/humanize/scripts/native-rlcr.py" ]]; then
    pass "Codex install includes deterministic native runtime"
else
    fail "Codex install includes deterministic native runtime"
fi

if [[ ! -d "$CODEX_SKILLS_DIR/humanize/hooks" ]]; then
    pass "Codex runtime does not install legacy hook scripts"
else
    fail "Codex runtime does not install legacy hook scripts" "no hooks directory" "present"
fi

if [[ ! -s "$FEATURE_LOG" ]]; then
    pass "Codex installer never invokes the Codex CLI"
else
    fail "Codex installer never invokes the Codex CLI" "empty invocation log" "$(cat "$FEATURE_LOG")"
fi

PY_OUTPUT="$(python3 - "$HOOKS_FILE" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
commands = []
for group in data.get("hooks", {}).get("Stop", []):
    for hook in group.get("hooks", []):
        if isinstance(hook, dict) and isinstance(hook.get("command"), str):
            commands.append(hook["command"])
print("MANAGED=" + str(sum("/humanize/hooks/" in value for value in commands)))
print("KEEP=" + ("1" if "/custom/keep-me.sh" in commands else "0"))
print("SESSION=" + ("1" if data["hooks"]["SessionStart"][0]["hooks"][0]["command"] == "/custom/session-start.sh" else "0"))
PY
)"

if grep -q '^MANAGED=0$' <<<"$PY_OUTPUT"; then
    pass "Codex install removes stale Humanize Stop hooks"
else
    fail "Codex install removes stale Humanize Stop hooks" "MANAGED=0" "$PY_OUTPUT"
fi
if grep -q '^KEEP=1$' <<<"$PY_OUTPUT"; then
    pass "Codex install preserves unrelated Stop hooks"
else
    fail "Codex install preserves unrelated Stop hooks" "KEEP=1" "$PY_OUTPUT"
fi
if grep -q '^SESSION=1$' <<<"$PY_OUTPUT"; then
    pass "Codex install preserves unrelated hook groups"
else
    fail "Codex install preserves unrelated hook groups" "SESSION=1" "$PY_OUTPUT"
fi

if grep -q '{{HUMANIZE_RUNTIME_ROOT}}' "$CODEX_SKILLS_DIR/humanize-rlcr/SKILL.md"; then
    fail "Installed Codex skill hydrates runtime root" "no placeholder" "placeholder remains"
else
    pass "Installed Codex skill hydrates runtime root"
fi

if grep -qE '^(user-invocable|disable-model-invocation|hide-from-slash-command-tool):' "$CODEX_SKILLS_DIR/humanize-rlcr/SKILL.md"; then
    fail "Installed Codex skill strips Claude-only frontmatter"
else
    pass "Installed Codex skill strips Claude-only frontmatter"
fi

NORMALIZED_COMPARE="$(python3 - "$PROJECT_ROOT/codex-skills/humanize-rlcr/SKILL.md" "$CODEX_SKILLS_DIR/humanize-rlcr/SKILL.md" "$CODEX_SKILLS_DIR/humanize" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
installed = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
runtime_root = sys.argv[3]
source = source.replace("{{HUMANIZE_RUNTIME_ROOT}}", runtime_root)
lines = []
in_frontmatter = False
frontmatter_done = False
for line in source.splitlines():
    if line.strip() == "---" and not frontmatter_done:
        in_frontmatter = not in_frontmatter
        if not in_frontmatter:
            frontmatter_done = True
        lines.append(line)
        continue
    if in_frontmatter and line.startswith(("user-invocable:", "disable-model-invocation:", "hide-from-slash-command-tool:")):
        continue
    lines.append(line)
normalized = "\n".join(lines) + ("\n" if source.endswith("\n") else "")
print("MATCH=1" if normalized == installed else "MATCH=0")
PY
)"
if [[ "$NORMALIZED_COMPARE" == "MATCH=1" ]]; then
    pass "Installed Codex skill matches the hydrated source skill"
else
    fail "Installed Codex skill matches the hydrated source skill" "MATCH=1" "$NORMALIZED_COMPARE"
fi

HUMANIZE_USER_CONFIG="$XDG_CONFIG_HOME_DIR/humanize/config.json"
if [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["provider_mode"])' "$HUMANIZE_USER_CONFIG")" == "codex-only" ]]; then
    pass "Codex install preserves provider_mode configuration"
else
    fail "Codex install preserves provider_mode configuration"
fi

if [[ -x "$COMMAND_BIN_DIR/bitlesson-selector" ]]; then
    pass "Codex install keeps the BitLesson selector shim"
else
    fail "Codex install keeps the BitLesson selector shim"
fi

# Reinstall to verify hook cleanup and skill synchronization are idempotent.
PATH="$FAKE_BIN:$PATH" \
TEST_CODEX_INVOCATION_LOG="$FEATURE_LOG" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$CODEX_HOME_DIR" \
    --codex-skills-dir "$CODEX_SKILLS_DIR" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install-2.log" 2>&1

if [[ ! -s "$FEATURE_LOG" ]] && ! grep -q '/humanize/hooks/' "$HOOKS_FILE"; then
    pass "Codex native install is idempotent"
else
    fail "Codex native install is idempotent"
fi

# Provider separation: Kimi keeps the existing shared skill while Codex gets the native skill.
KIMI_DIR="$TEST_DIR/kimi-skills"
CODEX_DIR_2="$TEST_DIR/codex-skills-2"
CODEX_CONFIG_2="$TEST_DIR/codex-config-2"
PATH="$FAKE_BIN:$PATH" \
TEST_CODEX_INVOCATION_LOG="$FEATURE_LOG" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target both \
    --kimi-skills-dir "$KIMI_DIR" \
    --codex-skills-dir "$CODEX_DIR_2" \
    --codex-config-dir "$CODEX_CONFIG_2" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install-both.log" 2>&1

if grep -q "native Stop hook" "$KIMI_DIR/humanize-rlcr/SKILL.md" && grep -q "Humanize Native RLCR Coordinator" "$CODEX_DIR_2/humanize-rlcr/SKILL.md"; then
    pass "Provider-specific install preserves Kimi while enabling native Codex RLCR"
else
    fail "Provider-specific install preserves Kimi while enabling native Codex RLCR"
fi

if python3 "$PROJECT_ROOT/tests/test-native-subagent-skills.py" > "$TEST_DIR/native-skill-contracts.log" 2>&1; then
    pass "Codex native skill delegation contracts pass"
else
    fail "Codex native skill delegation contracts pass" "success" "$(cat "$TEST_DIR/native-skill-contracts.log")"
fi

if python3 "$PROJECT_ROOT/tests/test-native-rlcr.py" > "$TEST_DIR/native-rlcr.log" 2>&1; then
    pass "Codex native RLCR state-machine tests pass"
else
    fail "Codex native RLCR state-machine tests pass" "success" "$(cat "$TEST_DIR/native-rlcr.log")"
fi

print_test_summary "Codex Native Install Tests"
