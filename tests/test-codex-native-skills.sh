#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
PASSED=0
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
contains() {
  local file="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" "$file"; then pass "$label"; else fail "$label"; fi
}
not_contains_regex() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$file"; then fail "$label"; else pass "$label"; fi
}

GEN="$ROOT/codex/skills/humanize-gen-plan/SKILL.md"
REFINE="$ROOT/codex/skills/humanize-refine-plan/SKILL.md"
RLCR="$ROOT/codex/skills/humanize-rlcr/SKILL.md"
ROUTER="$ROOT/codex/skills/humanize/SKILL.md"
CONSULT="$ROOT/codex/skills/humanize-consult/SKILL.md"
INSTALLER="$ROOT/scripts/install-codex-native.sh"

for file in "$GEN" "$REFINE" "$RLCR" "$ROUTER" "$CONSULT"; do
  [[ -f "$file" ]] && pass "source skill exists: ${file#$ROOT/}" || fail "source skill exists: ${file#$ROOT/}"
  contains "$file" 'model' "skill discusses runtime model selection: ${file#$ROOT/}"
  contains "$file" 'reasoning_effort' "skill discusses actual reasoning_effort field: ${file#$ROOT/}"
  contains "$file" 'fork_turns: "none"' "skill defines V2 non-full fork: ${file#$ROOT/}"
  contains "$file" 'fork_context: false' "skill defines V1 non-full fork: ${file#$ROOT/}"
  contains "$file" 'omit `model` and `reasoning_effort`' "skill preserves inheritance by omission: ${file#$ROOT/}"
  not_contains_regex "$file" 'gpt-[0-9]|o[0-9]-|model[[:space:]]*=[[:space:]]*"[^<]' "skill pins no concrete subagent model: ${file#$ROOT/}"
done

contains "$GEN" 'Parent work while the child runs' 'gen-plan requires useful parent work before join'
contains "$GEN" 'Collect the child before' 'gen-plan joins before final synthesis'
contains "$GEN" 'CURRENT_IMPLEMENTATION' 'gen-plan requires structured repository evidence'
contains "$GEN" 'validate-gen-plan-io.sh' 'gen-plan preserves validator'
contains "$GEN" 'Acceptance Criteria' 'gen-plan preserves output schema'

contains "$REFINE" 'research_request' 'refine-plan delegates only research_request work'
contains "$REFINE" 'Parent work while research runs' 'refine-plan requires useful parent work before join'
contains "$REFINE" 'atomic replace' 'refine-plan preserves atomic output behavior'
contains "$REFINE" 'validate-refine-plan-io.sh' 'refine-plan preserves validator'
contains "$REFINE" 'exactly one ledger row per raw `CMT-N`' 'refine-plan preserves QA ledger ownership'

for role in humanize_worker humanize_researcher humanize_implementation_reviewer humanize_code_reviewer; do
  contains "$RLCR" "$role" "RLCR owns native role $role"
done
contains "$RLCR" 'actual `spawn_agent` fields' 'RLCR requires real tool parameter overrides'
contains "$RLCR" 'While research runs' 'RLCR parent continues useful work during research'
contains "$RLCR" 'While the worker runs' 'RLCR parent continues useful work during implementation'
contains "$RLCR" 'fresh `humanize_implementation_reviewer`' 'RLCR uses independent implementation review thread'
contains "$RLCR" 'fresh `humanize_code_reviewer`' 'RLCR uses independent code review thread'
contains "$RLCR" 'Never finalize from worker completion' 'RLCR does not finalize before independent integration'
contains "$RLCR" 'native-rlcr.py' 'RLCR uses deterministic state machine'
not_contains_regex "$RLCR" '(^|[[:space:]])codex[[:space:]]+(exec|review)[[:space:]]+[-"$]' 'RLCR contains no executable nested Codex command'

for agent in humanize-worker humanize-researcher humanize-implementation-reviewer humanize-code-reviewer; do
  file="$ROOT/codex/agents/$agent.toml"
  [[ -f "$file" ]] && pass "custom agent exists: $agent" || fail "custom agent exists: $agent"
  not_contains_regex "$file" '^[[:space:]]*(model|model_reasoning_effort)[[:space:]]*=' "custom agent pins no model policy: $agent"
done
contains "$ROOT/codex/agents/humanize-worker.toml" 'sandbox_mode = "workspace-write"' 'worker owns bounded writes'
for agent in humanize-researcher humanize-implementation-reviewer humanize-code-reviewer; do
  contains "$ROOT/codex/agents/$agent.toml" 'sandbox_mode = "read-only"' "$agent is read-only"
done

contains "$INSTALLER" '$NATIVE_SKILLS_ROOT/humanize-gen-plan/SKILL.md' 'installer validates native gen-plan source'
contains "$INSTALLER" '$NATIVE_SKILLS_ROOT/humanize-refine-plan/SKILL.md' 'installer validates native refine-plan source'
contains "$INSTALLER" 'sync_dir "$NATIVE_SKILLS_ROOT/humanize-gen-plan"' 'installer installs native gen-plan'
contains "$INSTALLER" 'sync_dir "$NATIVE_SKILLS_ROOT/humanize-refine-plan"' 'installer installs native refine-plan'
not_contains_regex "$INSTALLER" 'sync_dir "\$SHARED_SKILLS_ROOT/humanize-(gen|refine)-plan"' 'Codex installer does not install shared planning skills'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash "$INSTALLER" \
  --repo-root "$ROOT" \
  --codex-skills-dir "$TMP/skills" \
  --codex-config-dir "$TMP/codex" \
  --codex-agents-dir "$TMP/agents" \
  --command-bin-dir "$TMP/bin" >/dev/null

for skill in humanize humanize-consult humanize-gen-plan humanize-refine-plan humanize-rlcr; do
  installed="$TMP/skills/$skill/SKILL.md"
  [[ -f "$installed" ]] && pass "installed skill exists: $skill" || fail "installed skill exists: $skill"
  if grep -q '{{HUMANIZE_RUNTIME_ROOT}}' "$installed"; then fail "installed skill is hydrated: $skill"; else pass "installed skill is hydrated: $skill"; fi
done
for agent in humanize-worker humanize-researcher humanize-implementation-reviewer humanize-code-reviewer; do
  [[ -f "$TMP/agents/$agent.toml" ]] && pass "installed agent exists: $agent" || fail "installed agent exists: $agent"
done
contains "$TMP/skills/humanize-rlcr/SKILL.md" 'actual `spawn_agent` fields' 'installed RLCR preserves runtime override contract'
contains "$TMP/skills/humanize-gen-plan/SKILL.md" 'Parent work while the child runs' 'installed gen-plan preserves parallel parent work'
contains "$TMP/skills/humanize-refine-plan/SKILL.md" 'atomic replace' 'installed refine-plan preserves transaction contract'

printf '\nPassed: %d\nFailed: %d\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
