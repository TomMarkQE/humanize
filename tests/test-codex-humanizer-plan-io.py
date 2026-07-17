#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "codex-humanizer-plan-io.py"

PURE_PLAN = """# Plan

## Goal Description
Do the work.

## Acceptance Criteria
- AC-1: pass.

## Path Boundaries
### Upper Bound (Maximum Acceptable Scope)
Complete.
### Lower Bound (Minimum Acceptable Scope)
Minimal.
### Allowed Choices
- standard library.

## Feasibility Hints and Suggestions
Use current patterns.

## Dependencies and Sequence
Task 1 first.

## Task Breakdown
| Task ID | Description | Target AC | Tag (`coding`/`analyze`) | Depends On |
|---|---|---|---|---|
| task1 | work | AC-1 | coding | - |

## Pending User Decisions
- none

## Implementation Notes
Keep code clear.
"""


class PlanIoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def invoke(self, *args):
        return subprocess.run(
            [sys.executable, str(VALIDATOR), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_gen_rejects_existing_output(self):
        draft = self.root / "draft.md"
        out = self.root / "plan.md"
        draft.write_text("draft\n", encoding="utf-8")
        out.write_text("exists\n", encoding="utf-8")
        proc = self.invoke("gen", "--input", str(draft), "--output", str(out))
        self.assertEqual(proc.returncode, 4)
        self.assertEqual(json.loads(proc.stdout)["kind"], "OUTPUT_EXISTS")

    def test_refine_accepts_pure_codex_schema(self):
        plan = self.root / "plan.md"
        plan.write_text(PURE_PLAN + "\nCMT:\nCheck app.py.\nENDCMT\n", encoding="utf-8")
        proc = self.invoke("refine", "--input", str(plan), "--qa-dir", str(self.root / "qa"))
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["comment_count"], 1)

    def test_refine_rejects_legacy_deliberation(self):
        plan = self.root / "plan.md"
        plan.write_text(
            PURE_PLAN + "\n## Claude-Codex Deliberation\nlegacy\n\nCMT:\nCheck app.py.\nENDCMT\n",
            encoding="utf-8",
        )
        proc = self.invoke("refine", "--input", str(plan), "--qa-dir", str(self.root / "qa"))
        self.assertEqual(proc.returncode, 4)
        self.assertEqual(json.loads(proc.stdout)["kind"], "LEGACY_DELIBERATION_SECTION")

    def test_refine_rejects_nested_comment(self):
        plan = self.root / "plan.md"
        plan.write_text(PURE_PLAN + "\nCMT:\nouter <cmt>inner</cmt>\nENDCMT\n", encoding="utf-8")
        proc = self.invoke("refine", "--input", str(plan), "--qa-dir", str(self.root / "qa"))
        self.assertEqual(proc.returncode, 3)
        self.assertEqual(json.loads(proc.stdout)["kind"], "NESTED_COMMENT")


if __name__ == "__main__":
    unittest.main(verbosity=2)
