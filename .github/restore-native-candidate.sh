#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

root = Path.cwd()
installer = root / "scripts/install-codex-native.sh"
text = installer.read_text(encoding="utf-8")
replacements = {
    '    "$SHARED_SKILLS_ROOT/humanize-gen-plan/SKILL.md" \\\n    "$SHARED_SKILLS_ROOT/humanize-refine-plan/SKILL.md" \\\n': '    "$NATIVE_SKILLS_ROOT/humanize-gen-plan/SKILL.md" \\\n    "$NATIVE_SKILLS_ROOT/humanize-refine-plan/SKILL.md" \\\n',
    'sync_dir "$SHARED_SKILLS_ROOT/humanize-gen-plan" "$CODEX_SKILLS_DIR/humanize-gen-plan"\nsync_dir "$SHARED_SKILLS_ROOT/humanize-refine-plan" "$CODEX_SKILLS_DIR/humanize-refine-plan"\n': 'sync_dir "$NATIVE_SKILLS_ROOT/humanize-gen-plan" "$CODEX_SKILLS_DIR/humanize-gen-plan"\nsync_dir "$NATIVE_SKILLS_ROOT/humanize-refine-plan" "$CODEX_SKILLS_DIR/humanize-refine-plan"\n',
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"installer patch anchor missing: {old!r}")
    text = text.replace(old, new, 1)
installer.write_text(text, encoding="utf-8", newline="\n")

runner = root / "tests/run-all-tests.py"
runner_text = runner.read_text(encoding="utf-8")
if '"test-disable-nested-codex-hooks.sh"",' not in runner_text:
    raise SystemExit("test runner typo anchor missing")
runner_text = runner_text.replace(
    '"test-disable-nested-codex-hooks.sh"",',
    '"test-disable-nested-codex-hooks.sh",\n    "test-codex-native-skills.sh",',
    1,
)
runner.write_text(runner_text, encoding="utf-8", newline="\n")
PY

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add scripts/install-codex-native.sh tests/run-all-tests.py
git diff --cached --quiet && exit 0
git commit -m "Install Codex-native planning skills"
git push origin HEAD:agent/runtime-selected-native-subagents
