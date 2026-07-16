#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "scripts" / "native-rlcr.py"


class NativeRlcrTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = pathlib.Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Humanize Test")
        (self.repo / ".gitignore").write_text(".humanize/\n", encoding="utf-8")
        (self.repo / "app.py").write_text("def value():\n    return 1\n", encoding="utf-8")
        (self.repo / "plan.md").write_text(
            "# Native RLCR test\n\n"
            "## Goal Description\nImprove the value implementation.\n\n"
            "## Acceptance Criteria\n- AC-1: value returns the requested result.\n\n"
            "## Task Breakdown\n- Update and test app.py.\n",
            encoding="utf-8",
        )
        self.git("add", ".")
        self.git("commit", "-q", "-m", "initial")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", "-C", str(self.repo), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        ).stdout.strip()

    def cli(self, *args, ok=True):
        proc = subprocess.run(
            [sys.executable, str(RUNTIME), *args],
            cwd=self.repo,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if ok and proc.returncode != 0:
            self.fail(f"command failed ({proc.returncode}): {' '.join(args)}\nstdout={proc.stdout}\nstderr={proc.stderr}")
        if not ok and proc.returncode == 0:
            self.fail(f"command unexpectedly succeeded: {' '.join(args)}\nstdout={proc.stdout}")
        return proc

    def write(self, name, text):
        path = pathlib.Path(self.tmp.name) / name
        path.write_text(text, encoding="utf-8")
        return path

    def start(self, *extra):
        result = self.cli("start", "--repo", str(self.repo), "--plan", "plan.md", *extra)
        payload = json.loads(result.stdout)
        return pathlib.Path(payload["run_dir"]), payload

    def worker_summary(self, round_number):
        return self.write(
            f"worker-{round_number}.md",
            f"# Round {round_number} Summary\n\n"
            "## What Was Implemented\nChanged app.py.\n\n"
            "## Files Changed\n- app.py\n\n"
            "## Validation\n- `python -m py_compile app.py` — passed\n\n"
            "## Remaining Items\n- none\n\n"
            "## BitLesson Delta\nAction: none\nLesson ID(s): NONE\nNotes: no reusable lesson\n",
        )

    def contract(self, round_number):
        return self.write(
            f"contract-{round_number}.md",
            f"# Round {round_number} Contract\n\n"
            "Mainline Objective: update app.py for AC-1\n"
            "Target ACs: AC-1\n"
            "Blocking Side Issues In Scope: none\n"
            "Queued Side Issues Out of Scope: unrelated cleanup\n"
            "Success Criteria: committed implementation and validation evidence\n",
        )

    def commit_value(self, value, message):
        (self.repo / "app.py").write_text(f"def value():\n    return {value}\n", encoding="utf-8")
        self.git("add", "app.py")
        self.git("commit", "-q", "-m", message)

    def test_complete_native_coordinator_state_machine(self):
        run_dir, started = self.start("--track-plan-file", "--max", "5")
        state_text = (run_dir / "state.md").read_text(encoding="utf-8")
        self.assertIn('orchestration_mode: "native_subagents"', state_text)
        self.assertIn('codex_model: ""', state_text)
        self.assertIn('codex_effort: ""', state_text)
        self.assertEqual(started["phase"], "implementation")

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "research")
        research = self.write(
            "research.md",
            "## Findings\n- value currently returns 1\n\n"
            "## Evidence\n- `app.py:2` — current return value\n\n"
            "## Implications\n- worker should update the return value\n\n"
            "## Unknowns\n- none\n",
        )
        self.cli("record-research", "--run-dir", str(run_dir), "--result", str(research))
        self.assertTrue((run_dir / "round-0-research.md").is_file())

        self.cli(
            "prepare-stage",
            "--run-dir",
            str(run_dir),
            "--stage",
            "worker",
            "--contract",
            str(self.contract(0)),
        )
        self.commit_value(2, "round 0")
        self.cli("record-worker", "--run-dir", str(run_dir), "--result", str(self.worker_summary(0)))

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "implementation-review")
        review_continue = self.write(
            "impl-continue.md",
            "# Implementation Review\n\n"
            "Verdict: CONTINUE\n"
            "Mainline Progress: ADVANCED\n\n"
            "## Verified Evidence\n- commit exists\n\n"
            "## Acceptance-Criteria Status\n- AC-1 partial\n\n"
            "## Blocking Issues\n- add final result\n\n"
            "## Queued Follow-up\n- none\n\n"
            "## Required Next Objective\n- finish AC-1\n\n"
            "CONTINUE\n",
        )
        continued = json.loads(
            self.cli(
                "record-implementation-review",
                "--run-dir",
                str(run_dir),
                "--result",
                str(review_continue),
            ).stdout
        )
        self.assertEqual(continued["round"], 1)
        self.assertEqual(continued["phase"], "implementation")

        self.cli(
            "prepare-stage",
            "--run-dir",
            str(run_dir),
            "--stage",
            "worker",
            "--contract",
            str(self.contract(1)),
        )
        self.commit_value(3, "round 1")
        self.cli("record-worker", "--run-dir", str(run_dir), "--result", str(self.worker_summary(1)))
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "implementation-review")
        review_complete = self.write(
            "impl-complete.md",
            "# Implementation Review\n\n"
            "Verdict: COMPLETE\n"
            "Mainline Progress: COMPLETE\n\n"
            "## Verified Evidence\n- app.py committed and validation passed\n\n"
            "## Acceptance-Criteria Status\n- AC-1 satisfied\n\n"
            "## Blocking Issues\n- none\n\n"
            "## Queued Follow-up\n- none\n\n"
            "## Required Next Objective\n- independent code review\n\n"
            "COMPLETE\n",
        )
        completed = json.loads(
            self.cli(
                "record-implementation-review",
                "--run-dir",
                str(run_dir),
                "--result",
                str(review_complete),
            ).stdout
        )
        self.assertEqual(completed["phase"], "code-review")

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "code-review")
        base = completed["base_commit"]
        head = self.git("rev-parse", "HEAD")
        changes = self.write(
            "code-changes.md",
            "# Code Review\n\n"
            "Verdict: CHANGES_REQUESTED\n"
            f"Review Base: {base}\n"
            f"Head Commit: {head}\n\n"
            "## Findings\n- [P2] `app.py:2` — return value needs one final correction\n\n"
            "## Validation Gaps\n- none\n\n"
            "## Non-blocking Notes\n- none\n\n"
            "CHANGES_REQUESTED\n",
        )
        code_fix = json.loads(
            self.cli("record-code-review", "--run-dir", str(run_dir), "--result", str(changes)).stdout
        )
        self.assertEqual(code_fix["phase"], "code-fix")

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "worker")
        self.commit_value(4, "code review fix")
        self.cli("record-worker", "--run-dir", str(run_dir), "--result", str(self.worker_summary(2)))
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "code-review")
        head = self.git("rev-parse", "HEAD")
        passed = self.write(
            "code-pass.md",
            "# Code Review\n\n"
            "Verdict: PASS\n"
            f"Review Base: {base}\n"
            f"Head Commit: {head}\n\n"
            "## Findings\n- none\n\n"
            "## Validation Gaps\n- none\n\n"
            "## Non-blocking Notes\n- none\n\n"
            "PASS\n",
        )
        finalize = json.loads(
            self.cli("record-code-review", "--run-dir", str(run_dir), "--result", str(passed)).stdout
        )
        self.assertEqual(finalize["phase"], "finalize")
        self.assertTrue((run_dir / "finalize-state.md").is_file())

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "finalize")
        final_result = self.write(
            "finalize.md",
            "# Finalize Summary\n\n"
            "## Simplifications\n- no additional code changes\n\n"
            "## Validation\n- repository is clean\n\n"
            "## Remaining Risks\n- none\n",
        )
        final = json.loads(
            self.cli("record-finalize", "--run-dir", str(run_dir), "--result", str(final_result)).stdout
        )
        self.assertEqual(final["status"], "complete")
        self.assertTrue((run_dir / "complete-state.md").is_file())
        self.assertFalse((run_dir / "state.md").exists())
        self.assertFalse((run_dir / "finalize-state.md").exists())

    def test_read_only_reviewer_guard_detects_changes(self):
        run_dir, _ = self.start()
        self.cli(
            "prepare-stage",
            "--run-dir",
            str(run_dir),
            "--stage",
            "worker",
            "--contract",
            str(self.contract(0)),
        )
        self.commit_value(2, "worker")
        self.cli("record-worker", "--run-dir", str(run_dir), "--result", str(self.worker_summary(0)))
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "implementation-review")
        (self.repo / "app.py").write_text("def value():\n    return 999\n", encoding="utf-8")
        review = self.write(
            "guard-review.md",
            "Verdict: CONTINUE\nMainline Progress: ADVANCED\n\nCONTINUE\n",
        )
        failed = self.cli(
            "record-implementation-review",
            "--run-dir",
            str(run_dir),
            "--result",
            str(review),
            ok=False,
        )
        self.assertIn("read-only child changed repository state", failed.stderr)

    def test_tracked_plan_integrity_is_enforced(self):
        run_dir, _ = self.start("--track-plan-file")
        (self.repo / "plan.md").write_text("tampered\n", encoding="utf-8")
        failed = self.cli("status", "--run-dir", str(run_dir), ok=False)
        self.assertIn("tracked source plan changed", failed.stderr)

    def test_code_review_pass_rejects_priority_finding(self):
        run_dir, started = self.start("--review-only")
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "code-review")
        head = self.git("rev-parse", "HEAD")
        result = self.write(
            "invalid-pass.md",
            "Verdict: PASS\n"
            f"Review Base: {started['base_commit']}\n"
            f"Head Commit: {head}\n\n"
            "## Findings\n- [P1] unresolved\n\nPASS\n",
        )
        failed = self.cli("record-code-review", "--run-dir", str(run_dir), "--result", str(result), ok=False)
        self.assertIn("PASS code review contains blocking priority findings", failed.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
