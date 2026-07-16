#!/usr/bin/env python3
"""Portable, fail-closed test runner for the Humanize repository.

The repository's test suites are shell scripts, but the orchestrator must also
work with macOS's Bash 3.2.  Python owns scheduling and result collection so a
runner exception, a missing suite, a timeout, or a missing result can never be
reported as success.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

TEST_SUITES: Tuple[str, ...] = (
    "test-template-loader.sh",
    "test-bash-validator-patterns.sh",
    "test-todo-checker.sh",
    "test-plan-file-validation.sh",
    "test-template-references.sh",
    "test-state-exit-naming.sh",
    "test-stop-gate.sh",
    "test-templates-comprehensive.sh",
    "test-plan-file-hooks.sh",
    "test-stop-hook-legacy-compat.sh",
    "test-stop-hook-bg-allow.sh",
    "test-error-scenarios.sh",
    "test-ansi-parsing.sh",
    "test-allowlist-validators.sh",
    "test-finalize-phase.sh",
    "test-codex-review-merge.sh",
    "test-cancel-signal-file.sh",
    "test-humanize-escape.sh",
    "test-zsh-monitor-safety.sh",
    "test-monitor-runtime.sh",
    "test-monitor-e2e-deletion.sh",
    "test-monitor-e2e-sigint.sh",
    "test-gen-plan.sh",
    "test-refine-plan.sh",
    "test-task-tag-routing.sh",
    "test-config-merge.sh",
    "test-config-error-handling.sh",
    "test-test-runner.sh",
    "test-codex-native-runtime.sh",
    "test-codex-hook-install.sh",
    "test-unified-codex-config.sh",
    "test-disable-nested-codex-hooks.sh"",
    "test-session-id.sh",
    "test-agent-teams.sh",
    "test-ask-codex.sh",
    "test-bitlesson-select-routing.sh",
    "test-model-router.sh",
    "test-skill-monitor.sh",
    "robustness/test-state-file-robustness.sh",
    "robustness/test-session-robustness.sh",
    "robustness/test-goal-tracker-robustness.sh",
    "robustness/test-path-validation-robustness.sh",
    "robustness/test-git-operations-robustness.sh",
    "robustness/test-hook-input-robustness.sh",
    "robustness/test-template-stress-robustness.sh",
    "robustness/test-plan-file-robustness.sh",
    "robustness/test-cancel-security-robustness.sh",
    "robustness/test-timeout-robustness.sh",
    "robustness/test-base-branch-detection.sh",
    "robustness/test-setup-scripts-robustness.sh",
    "robustness/test-concurrent-state-robustness.sh",
    "robustness/test-hook-system-robustness.sh",
    "robustness/test-template-error-robustness.sh",
    "robustness/test-state-transition-robustness.sh",
)

ZSH_TESTS = frozenset({"test-zsh-monitor-safety.sh"})
PASSED_RE = re.compile(r"(?:^|\n)(?:Total )?Passed:\s*([0-9]+)", re.IGNORECASE)
FAILED_RE = re.compile(r"(?:^|\n)(?:Total )?Failed:\s*([0-9]+)", re.IGNORECASE)
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


@dataclass(frozen=True)
class Result:
    suite: str
    status: str
    exit_code: int
    duration: float
    output: str
    passed: int = 0
    failed: int = 0
    reason: str = ""


def positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if value < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return value


def default_jobs() -> int:
    return max(1, min(os.cpu_count() or 4, 8))


def build_environment(temp_root: Path) -> Dict[str, str]:
    env = os.environ.copy()
    if shutil.which("codex", path=env.get("PATH")) is None:
        mock_bin = temp_root / "mock-bin"
        mock_bin.mkdir(parents=True, exist_ok=True)
        mock_codex = mock_bin / "codex"
        mock_codex.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        mock_codex.chmod(0o755)
        env["PATH"] = str(mock_bin) + os.pathsep + env.get("PATH", "")
    return env


def last_count(pattern: re.Pattern[str], output: str) -> int:
    values = pattern.findall(ANSI_RE.sub("", output))
    return int(values[-1]) if values else 0


def run_suite(
    tests_dir: Path,
    suite: str,
    timeout_seconds: int,
    environment: Dict[str, str],
) -> Result:
    start = time.monotonic()
    path = tests_dir / suite
    if not path.is_file():
        return Result(
            suite=suite,
            status="failed",
            exit_code=127,
            duration=time.monotonic() - start,
            output="",
            reason="listed test suite is missing",
        )

    if suite in ZSH_TESTS:
        shell = shutil.which("zsh", path=environment.get("PATH"))
        if shell is None:
            return Result(
                suite=suite,
                status="skipped",
                exit_code=0,
                duration=time.monotonic() - start,
                output="",
                reason="zsh is not installed",
            )
    else:
        shell = shutil.which("bash", path=environment.get("PATH"))
        if shell is None:
            return Result(
                suite=suite,
                status="failed",
                exit_code=127,
                duration=time.monotonic() - start,
                output="",
                reason="bash is not installed",
            )

    try:
        completed = subprocess.run(
            [shell, str(path)],
            cwd=str(tests_dir.parent),
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        return Result(
            suite=suite,
            status="failed",
            exit_code=124,
            duration=time.monotonic() - start,
            output=partial,
            reason="timed out after %d seconds" % timeout_seconds,
        )
    except Exception as exc:  # Fail closed on runner/launch errors.
        return Result(
            suite=suite,
            status="failed",
            exit_code=125,
            duration=time.monotonic() - start,
            output="",
            reason="runner exception: %s: %s" % (type(exc).__name__, exc),
        )

    output = completed.stdout or ""
    passed = last_count(PASSED_RE, output)
    failed = last_count(FAILED_RE, output)
    status = "passed" if completed.returncode == 0 and failed == 0 else "failed"
    reason = ""
    if completed.returncode != 0:
        reason = "suite exited with code %d" % completed.returncode
    elif failed:
        reason = "suite reported %d failed assertion(s)" % failed
    return Result(
        suite=suite,
        status=status,
        exit_code=completed.returncode,
        duration=time.monotonic() - start,
        output=output,
        passed=passed,
        failed=failed,
        reason=reason,
    )


def render_result(result: Result) -> str:
    label = {"passed": "PASSED", "failed": "FAILED", "skipped": "SKIP"}[result.status]
    details = "%s: %s (%.1fs" % (label, result.suite, result.duration)
    if result.status == "passed":
        details += ", %d assertions" % result.passed
    elif result.reason:
        details += ", %s" % result.reason
    return details + ")"


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--jobs",
        type=positive_int,
        default=positive_int(os.environ.get("HUMANIZE_TEST_JOBS", str(default_jobs()))),
        help="parallel suites (default: HUMANIZE_TEST_JOBS or detected CPU count, capped at 8)",
    )
    parser.add_argument(
        "--timeout",
        type=positive_int,
        default=positive_int(os.environ.get("HUMANIZE_TEST_TIMEOUT", "900")),
        help="per-suite timeout in seconds (default: 900)",
    )
    parser.add_argument(
        "suites",
        nargs="*",
        help="optional suite paths relative to tests/; default runs the maintained manifest",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    tests_dir = Path(__file__).resolve().parent
    suites = tuple(args.suites) if args.suites else TEST_SUITES
    if not suites:
        print("Error: no test suites selected", file=sys.stderr)
        return 2
    if len(set(suites)) != len(suites):
        print("Error: duplicate suite in test manifest or command line", file=sys.stderr)
        return 2

    print("=" * 56)
    print("Running Humanize tests")
    print("=" * 56)
    print("Parallel jobs: %d" % args.jobs)
    print("Per-suite timeout: %ds" % args.timeout)
    print("Suites: %d" % len(suites))
    print()

    try:
        with tempfile.TemporaryDirectory(prefix="humanize-tests-") as raw_temp:
            environment = build_environment(Path(raw_temp))
            results: List[Result] = []
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
                future_map = {
                    executor.submit(run_suite, tests_dir, suite, args.timeout, environment): suite
                    for suite in suites
                }
                for future in concurrent.futures.as_completed(future_map):
                    suite = future_map[future]
                    try:
                        result = future.result()
                    except Exception as exc:  # Defensive: worker exceptions are failures.
                        result = Result(
                            suite=suite,
                            status="failed",
                            exit_code=125,
                            duration=0.0,
                            output="",
                            reason="unhandled runner exception: %s: %s" % (type(exc).__name__, exc),
                        )
                    results.append(result)
    except Exception as exc:
        print("FATAL: test orchestrator failed: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 2

    results.sort(key=lambda item: (item.duration, item.suite))
    for result in results:
        print(render_result(result))

    failures = [result for result in results if result.status == "failed"]
    skipped = [result for result in results if result.status == "skipped"]
    total_passed = sum(result.passed for result in results)
    total_failed = sum(result.failed for result in results)

    if failures:
        print()
        print("=" * 56)
        print("Failed suite details")
        print("=" * 56)
        for result in failures:
            print("\n--- %s ---" % result.suite)
            if result.reason:
                print(result.reason)
            if result.output:
                print(result.output.rstrip())

    print()
    print("=" * 56)
    print("Test Summary")
    print("=" * 56)
    print("Suites passed: %d" % sum(result.status == "passed" for result in results))
    print("Suites failed: %d" % len(failures))
    print("Suites skipped: %d" % len(skipped))
    print("Assertions passed: %d" % total_passed)
    print("Assertions failed: %d" % total_failed)

    if failures:
        print("Some tests failed.")
        return 1
    print("All selected tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
