#!/usr/bin/env python3
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SKILLS = ROOT / "codex-skills"
NAMES = (
    "codex-humanizer",
    "codex-humanizer-gen-plan",
    "codex-humanizer-refine-plan",
    "codex-humanizer-rlcr",
)


class CodexHumanizerSkillContractTest(unittest.TestCase):
    def text(self, name):
        return (SKILLS / name / "SKILL.md").read_text(encoding="utf-8")

    def test_skill_names_and_runtime_root(self):
        for name in NAMES:
            path = SKILLS / name / "SKILL.md"
            self.assertTrue(path.is_file(), path)
            text = path.read_text(encoding="utf-8")
            self.assertIn(f"name: {name}", text)
            self.assertIn("{{HUMANIZE_RUNTIME_ROOT}}", text)

    def test_runtime_override_contract_uses_actual_fields_and_non_full_fork(self):
        for name in NAMES:
            text = self.text(name)
            self.assertIn("`model`", text, name)
            self.assertIn("`reasoning_effort`", text, name)
            self.assertIn('`fork_turns: "none"`', text, name)
            self.assertIn("`fork_context: false`", text, name)
            self.assertRegex(text, r"actual `?spawn_agent")

    def test_skill_content_does_not_pin_model_policy(self):
        forbidden = (
            r"gpt-[0-9]",
            r"o[0-9](?:-|\b)",
            r"default subagent model",
            r"default reasoning effort",
            r"codex_model:\s*\S+",
            r"codex_effort:\s*\S+",
        )
        for path in SKILLS.glob("*/SKILL.md"):
            text = path.read_text(encoding="utf-8").lower()
            for pattern in forbidden:
                self.assertIsNone(re.search(pattern, text), f"{path}: {pattern}")

    def test_pure_codex_plan_schema(self):
        for name in ("codex-humanizer-gen-plan", "codex-humanizer-refine-plan"):
            text = self.text(name)
            self.assertIn("## Pending User Decisions", text)
            self.assertIn("Coordinator Recommendation", text)
            self.assertIn("`## Claude-Codex Deliberation`", text)
            self.assertNotIn("Claude Position", text)
            self.assertNotIn("Codex Position", text)

    def test_gen_plan_has_research_and_fresh_plan_review(self):
        text = self.text("codex-humanizer-gen-plan")
        for required in (
            "## Phase 2: bounded repository evidence",
            "While it runs, the root must continue non-overlapping",
            "## Phase 4: fresh independent plan review",
            "VERDICT: REVISE | ACCEPT | BLOCKED",
            "perform at most one fresh confirmation review",
        ):
            self.assertIn(required, text)

    def test_refine_plan_delegates_only_research_requests(self):
        text = self.text("codex-humanizer-refine-plan")
        for required in (
            "Create a read-only child only when a `research_request`",
            "Each child owns only the listed `CMT-N` items",
            "## Root work while research runs",
            "## Join and integration gate",
            "atomic rename",
        ):
            self.assertIn(required, text)

    def test_rlcr_is_full_native_coordinator_without_legacy_controls(self):
        text = self.text("codex-humanizer-rlcr")
        for required in (
            "The live Codex root thread is the coordinator",
            "### Worker child",
            "### Research child",
            "### Implementation reviewer",
            "### Code reviewer",
            "followup_task",
            "record-implementation-review",
            "record-code-review",
            "complete-state.md",
            ".codex-humanizer/rlcr/",
        ):
            self.assertIn(required, text)
        for forbidden in ("codex exec", "codex review", "Stop hook", "BitLesson Delta", "--codex-model"):
            self.assertNotIn(forbidden, text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
