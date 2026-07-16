#!/usr/bin/env python3
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SKILLS = ROOT / "codex-skills"


class NativeSubagentSkillContractTest(unittest.TestCase):
    def text(self, name):
        return (SKILLS / name / "SKILL.md").read_text(encoding="utf-8")

    def test_all_codex_skills_are_provider_specific(self):
        for name in ("humanize", "humanize-gen-plan", "humanize-refine-plan", "humanize-rlcr"):
            path = SKILLS / name / "SKILL.md"
            self.assertTrue(path.is_file(), path)
            self.assertIn("{{HUMANIZE_RUNTIME_ROOT}}", path.read_text(encoding="utf-8"))

    def test_runtime_override_contract_uses_actual_fields_and_non_full_fork(self):
        for name in ("humanize", "humanize-gen-plan", "humanize-refine-plan", "humanize-rlcr"):
            text = self.text(name)
            self.assertIn("`model`", text, name)
            self.assertIn("`reasoning_effort`", text, name)
            self.assertIn('`fork_turns: "none"`', text, name)
            self.assertIn("`fork_context: false`", text, name)
            self.assertRegex(text, r"actual [`']?spawn_agent")

    def test_skill_content_does_not_pin_subagent_model_policy(self):
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

    def test_gen_plan_defines_complete_delegation_boundary(self):
        text = self.text("humanize-gen-plan")
        for required in (
            "## Delegation boundary",
            "The child owns only this bounded, read-only task",
            "### Required child result",
            "## Root work while the child runs",
            "## Join and integration point",
            "final relevance decision",
        ):
            self.assertIn(required, text)

    def test_refine_plan_delegates_only_research_requests(self):
        text = self.text("humanize-refine-plan")
        for required in (
            "## Delegation boundary for `research_request`",
            "Each child owns only the listed `CMT-N` items",
            "## Root work while research runs",
            "## Join and integration point",
            "write the refined plan, QA ledger, and language variants atomically",
        ):
            self.assertIn(required, text)

    def test_rlcr_is_full_native_coordinator(self):
        text = self.text("humanize-rlcr")
        for required in (
            "The current Codex root thread is the coordinator",
            "### Worker child",
            "### Research child",
            "### Implementation reviewer",
            "### Code reviewer",
            "followup_task",
            "record-implementation-review",
            "record-code-review",
            "complete-state.md",
            "The root may inspect files and run deterministic checks, but it must not edit implementation files",
        ):
            self.assertIn(required, text)
        self.assertNotIn("codex exec", text)
        self.assertNotIn("codex review", text)
        self.assertNotIn("Stop hook", text)

    def test_parent_continues_before_each_required_join(self):
        gen = self.text("humanize-gen-plan")
        refine = self.text("humanize-refine-plan")
        rlcr = self.text("humanize-rlcr")
        self.assertIn("Do not immediately wait", gen)
        self.assertIn("The root must continue useful, non-overlapping work", refine)
        self.assertIn("While research runs, the root must independently prepare", rlcr)
        self.assertIn("While the worker runs, the root must continue non-overlapping work", rlcr)
        self.assertIn("Do not finalize before required child evidence", self.text("humanize"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
