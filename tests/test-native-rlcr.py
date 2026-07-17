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
        self.git("config", "user.name", "Codex Humanizer Test")
        (self.repo / ".gitignore").write_text(".codex-humanizer/\n", encoding="utf-8")
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
            "## Remaining Items\n- none\n",
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

    def implementation_review(self, verdict, progress, next_objective):
        return self.write(
            f"impl-{verdict.lower()}.md",
            "# Implementation Review\n\n"
            f"Verdict: {verdict}\n"
            f"Mainline Progress: {progress}\n\n"
            "## Verified Evidence\n- commit and validation inspected\n\n"
            "## Acceptance-Criteria Status\n- AC-1 evaluated\n\n"
            "## Blocking Issues\n- none\n\n"
            "## Queued Follow-up\n- none\n\n"
            f"## Required Next Objective\n- {next_objective}\n\n"
            f"{verdict}\n",
        )

    def test_complete_native_coordinator_state_machine(self):
        run_dir, started = self.start("--track-plan-file", "--max-rounds", "5")
        self.assertIn(".codex-humanizer/rlcr", str(run_dir))
        state_text = (run_dir / "state.md").read_text(encoding="utf-8")
        self.assertIn('orchestration_mode: "codex_humanizer_native"', state_text)
        self.assertIn("max_rounds: 5", state_text)
        self.assertNotIn("codex_model", state_text)
        self.assertNotIn("bitlesson", state_text.lower())
        self.assertEqual(started["phase"], "implementation")

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "research")
        research = self.write(
            "research.md",
            "## Findings\n- value currently returns 1\n\n"
            "## Evidence\n- `app.py:2` — current return value\n\n"
            "## Implications\n- worker should update the value\n\n"
            "## Unknowns\n- none\n",
        )
        self.cli("record-research", "--run-dir", str(run_dir), "--result", str(research))

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "worker", "--contract", str(self.contract(0)))
        self.commit_value(2, "round 0")
        self.cli("record-worker", "--run-dir", str(run_dir), "--result", str(self.worker_summary(0)))
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "implementation-review")
        continued = json.loads(
            self.cli(
                "record-implementation-review",
                "--run-dir", str(run_dir),
                "--result", str(self.implementation_review("CONTINUE", "ADVANCED", "finish AC-1")),
            ).stdout
        )
        self.assertEqual(continued["round"], 1)

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "worker", "--contract", str(self.contract(1)))
        self.commit_value(3, "round 1")
        self.cli("record-worker", "--run-dir", str(run_dir), "--result", str(self.worker_summary(1)))
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "implementation-review")
        completed = json.loads(
            self.cli(
                "record-implementation-review",
                "--run-dir", str(run_dir),
                "--result", str(self.implementation_review("COMPLETE", "COMPLETE", "independent code review")),
            ).stdout
        )
        self.assertEqual(completed["phase"], "code-review")

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "code-review")
        base = completed["base_commit"]
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
        finalize = json.loads(self.cli("record-code-review", "--run-dir", str(run_dir), "--result", str(passed)).stdout)
        self.assertEqual(finalize["phase"], "finalize")

        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "finalize")
        final_result = self.write(
            "finalize.md",
            "# Finalize Summary\n\n"
            "## Simplifications\n- no additional changes\n\n"
            "## Validation\n- repository clean\n\n"
            "## Remaining Risks\n- none\n",
        )
        final = json.loads(self.cli("record-finalize", "--run-dir", str(run_dir), "--result", str(final_result)).stdout)
        self.assertEqual(final["status"], "complete")
        self.assertTrue((run_dir / "complete-state.md").is_file())

    def test_read_only_guard_detects_changes(self):
        run_dir, _ = self.start()
        self.cli("prepare-stage", "--run-dir", str(run_dir), "--stage", "research")
        (self.repo / "app.py").write_text("def value():\n    return 999\n", encoding="utf-8")
        result = self.write(
            "research.md",
            "## Findings\n- changed\n\n## Evidence\n- app.py\n\n## Implications\n- none\n\n## Unknowns\n- none\n",
        )
        failed = self.cli("record-research", "--run-dir", str(run_dir), "--result", str(result), ok=False)
        self.assertIn("read-only child changed repository state", failed.stderr)

    def test_review_only_and_legacy_aliases(self):
        result = self.cli("start", "--repo", str(self.repo), "--skip-impl", "--max", "2")
        payload = json.loads(result.stdout)
        self.assertEqual(payload["phase"], "code-review")
        self.assertEqual(payload["max_rounds"], 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
