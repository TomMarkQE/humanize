#!/usr/bin/env python3
"""Deterministic state machine for Humanize's Codex-native RLCR workflow.

This module deliberately performs no model invocation.  A Codex Skill owns
agent orchestration; this program only validates repository state, persists
round state, and parses the reviewers' stable result contracts.
"""

from __future__ import print_function

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

SCHEMA_VERSION = 1
ENGINE = "codex-native"
STATE_NAME = "state.json"
ACTIVE_STATUSES = {"active"}
TERMINAL_STATUSES = {"complete", "blocked", "failed", "cancelled"}
IMPLEMENTATION_MARKER = re.compile(
    r"^HUMANIZE_IMPLEMENTATION_REVIEW:\s*(continue|complete|blocked)\s*$",
    re.MULTILINE,
)
MAINLINE_MARKER = re.compile(
    r"^MAINLINE_PROGRESS:\s*(advanced|stalled|regressed)\s*$",
    re.MULTILINE,
)
CODE_MARKER = re.compile(
    r"^HUMANIZE_CODE_REVIEW:\s*(changes_required|pass|blocked)\s*$",
    re.MULTILINE,
)
PRIORITY_MARKER = re.compile(r"\[P[0-9]\]")


class HumanizeError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
        exit_code: int = 2,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}
        self.exit_code = exit_code


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        return sha256_bytes(path.read_bytes())
    except OSError as exc:
        raise HumanizeError(
            "io_error", "Unable to read file for hashing", {"path": str(path), "error": str(exc)}, 5
        )


def atomic_write_text(path: Path, content: str, mode: Optional[int] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".%s." % path.name, dir=str(path.parent))
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(str(temp_path), mode)
        os.replace(str(temp_path), str(path))
    except Exception:
        try:
            temp_path.unlink()
        except OSError:
            pass
        raise


def atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    atomic_write_text(path, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def append_json_line(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def run_git(
    project_root: Path,
    args: Sequence[str],
    allow_failure: bool = False,
    timeout: int = 30,
) -> subprocess.CompletedProcess:
    command = ["git", "-C", str(project_root)] + list(args)
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        raise HumanizeError("git_unavailable", "git is required for native RLCR", exit_code=4)
    except subprocess.TimeoutExpired:
        raise HumanizeError(
            "git_timeout", "git command timed out", {"command": command, "timeout": timeout}, 4
        )
    if result.returncode != 0 and not allow_failure:
        raise HumanizeError(
            "git_error",
            "git command failed",
            {
                "command": command,
                "exit_code": result.returncode,
                "stderr": result.stderr.strip(),
            },
            4,
        )
    return result


def resolve_project_root(raw_root: Optional[str]) -> Path:
    candidate = Path(raw_root or os.getcwd()).expanduser().resolve()
    result = run_git(candidate, ["rev-parse", "--show-toplevel"])
    root = Path(result.stdout.strip()).resolve()
    if not root.is_dir():
        raise HumanizeError("invalid_project_root", "Resolved project root is not a directory")
    return root


def relative_to_root(path: Path, root: Path, label: str) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        raise HumanizeError(
            "path_outside_project",
            "%s must be inside the project root" % label,
            {"path": str(path), "project_root": str(root)},
        )


def reject_symlink_path(path: Path, root: Path, label: str) -> None:
    relative = Path(relative_to_root(path, root, label))
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise HumanizeError(
                "symlink_not_allowed", "%s may not traverse a symbolic link" % label, {"path": str(current)}
            )


def resolve_plan(project_root: Path, raw_plan: str) -> Tuple[Path, str]:
    plan_candidate = Path(raw_plan).expanduser()
    if plan_candidate.is_absolute():
        plan = plan_candidate.resolve()
    else:
        plan = (project_root / plan_candidate).resolve()
    relative = relative_to_root(plan, project_root, "Plan file")
    reject_symlink_path(plan, project_root, "Plan file")
    if not plan.is_file():
        raise HumanizeError("plan_not_found", "Plan file does not exist", {"plan_file": relative})
    try:
        content = plan.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raise HumanizeError("plan_not_utf8", "Plan file must be UTF-8 text", {"plan_file": relative})
    except OSError as exc:
        raise HumanizeError("plan_unreadable", "Plan file is not readable", {"error": str(exc)})
    nonblank = [line for line in content.splitlines() if line.strip()]
    if len(nonblank) < 3:
        raise HumanizeError(
            "plan_too_small", "Plan file must contain at least three non-empty lines", {"plan_file": relative}
        )
    return plan, relative


def detect_branch(project_root: Path) -> str:
    result = run_git(project_root, ["symbolic-ref", "--quiet", "--short", "HEAD"], allow_failure=True)
    if result.returncode != 0 or not result.stdout.strip():
        raise HumanizeError(
            "detached_head",
            "Native RLCR requires a named branch so round checkpoints can be validated",
            exit_code=4,
        )
    return result.stdout.strip()


def ref_exists(project_root: Path, ref: str) -> bool:
    return run_git(project_root, ["rev-parse", "--verify", "%s^{commit}" % ref], allow_failure=True).returncode == 0


def detect_base_ref(project_root: Path, explicit: Optional[str], current_branch: str) -> str:
    if explicit:
        if not ref_exists(project_root, explicit):
            raise HumanizeError("base_ref_missing", "Base ref does not resolve to a commit", {"base_ref": explicit})
        return explicit
    for candidate in ("main", "master"):
        if ref_exists(project_root, candidate):
            return candidate
    # A repository with only one branch is still usable.  Its starting commit is
    # the comparison anchor and later round commits advance from it.
    return current_branch


def current_commit(project_root: Path) -> str:
    return run_git(project_root, ["rev-parse", "HEAD"]).stdout.strip()


def resolve_commit(project_root: Path, ref: str) -> str:
    return run_git(project_root, ["rev-parse", "%s^{commit}" % ref]).stdout.strip()


def normalized_status_path(raw: str) -> str:
    return raw.strip().strip('"')


def is_managed_path(raw: str) -> bool:
    path = normalized_status_path(raw)
    return path == ".humanize" or path.startswith(".humanize/")


def is_managed_status_line(line: str) -> bool:
    if len(line) < 4:
        return False
    payload = line[3:]
    if " -> " in payload:
        source, destination = payload.split(" -> ", 1)
        # A rename that crosses the .humanize boundary changes a real project
        # path and must never be hidden as runtime-only state.
        return is_managed_path(source) and is_managed_path(destination)
    return is_managed_path(payload)


def is_ignored_untracked_line(line: str, ignored_paths: Iterable[str]) -> bool:
    if not line.startswith("?? "):
        return False
    path = normalized_status_path(line[3:])
    return path in set(ignored_paths)


def unmanaged_git_changes(
    project_root: Path, ignored_untracked_paths: Iterable[str] = ()
) -> List[str]:
    result = run_git(project_root, ["status", "--porcelain=v1", "--untracked-files=all"])
    ignored = tuple(ignored_untracked_paths)
    return [
        line
        for line in result.stdout.splitlines()
        if line
        and not is_managed_status_line(line)
        and not is_ignored_untracked_line(line, ignored)
    ]


@contextlib.contextmanager
def exclusive_lock(path: Path) -> Iterable[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        handle = path.open("a+")
    except OSError as exc:
        raise HumanizeError("lock_unavailable", "Unable to open native RLCR lock", {"path": str(path), "error": str(exc)}, 5)
    try:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        except OSError as exc:
            raise HumanizeError("lock_unavailable", "Unable to acquire native RLCR lock", {"path": str(path), "error": str(exc)}, 5)
        yield
    finally:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        finally:
            handle.close()


def state_path(loop_dir: Path) -> Path:
    return loop_dir / STATE_NAME


def load_state(loop_dir: Path) -> Dict[str, Any]:
    path = state_path(loop_dir)
    if not path.is_file():
        raise HumanizeError("state_not_found", "Native RLCR state file was not found", {"state_file": str(path)})
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise HumanizeError("state_corrupt", "Native RLCR state JSON is invalid", {"error": str(exc)})
    except OSError as exc:
        raise HumanizeError("state_unreadable", "Native RLCR state file cannot be read", {"error": str(exc)})
    if not isinstance(state, dict):
        raise HumanizeError("state_corrupt", "Native RLCR state must be a JSON object")
    if state.get("schema_version") != SCHEMA_VERSION or state.get("engine") != ENGINE:
        raise HumanizeError(
            "state_incompatible",
            "State file is not a supported Codex-native RLCR state",
            {"schema_version": state.get("schema_version"), "engine": state.get("engine")},
        )
    return state


def save_state(loop_dir: Path, state: Dict[str, Any], event: str, event_data: Dict[str, Any]) -> None:
    state["updated_at"] = utc_now()
    atomic_write_json(state_path(loop_dir), state)
    append_json_line(
        loop_dir / "events.jsonl",
        {
            "at": state["updated_at"],
            "event": event,
            "round": state.get("round"),
            "phase": state.get("phase"),
            "status": state.get("status"),
            "data": event_data,
        },
    )


def active_native_loops(project_root: Path) -> List[Path]:
    base = project_root / ".humanize" / "rlcr"
    if not base.is_dir():
        return []
    active: List[Path] = []
    allowed_statuses = ACTIVE_STATUSES | TERMINAL_STATUSES
    for candidate in sorted(base.iterdir()):
        path = candidate / STATE_NAME
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise HumanizeError(
                "state_corrupt",
                "An existing native RLCR state file is unreadable or invalid",
                {"state_file": str(path), "error": str(exc)},
                3,
            )
        if not isinstance(data, dict):
            raise HumanizeError("state_corrupt", "An existing native RLCR state is not a JSON object", {"state_file": str(path)}, 3)
        if data.get("engine") != ENGINE:
            continue
        if data.get("status") not in allowed_statuses:
            raise HumanizeError(
                "state_corrupt",
                "An existing native RLCR state has an unsupported status",
                {"state_file": str(path), "status": data.get("status")},
                3,
            )
        if data.get("status") in ACTIVE_STATUSES:
            active.append(candidate)
    return active


def public_state(loop_dir: Path, state: Dict[str, Any], event: str, next_action: str) -> Dict[str, Any]:
    return {
        "ok": True,
        "event": event,
        "next_action": next_action,
        "loop_dir": str(loop_dir),
        "state_file": str(state_path(loop_dir)),
        "status": state.get("status"),
        "phase": state.get("phase"),
        "round": state.get("round"),
        "max_rounds": state.get("max_rounds"),
        "plan_snapshot": str(loop_dir / "plan.md"),
        "goal_tracker": str(loop_dir / "goal-tracker.md"),
        "summary_file": str(loop_dir / ("round-%s-summary.md" % state.get("round"))),
        "base_ref": state.get("base_ref"),
        "base_commit": state.get("base_commit"),
        "start_branch": state.get("start_branch"),
        "last_checkpoint_commit": state.get("last_checkpoint_commit"),
        "completed_at": state.get("completed_at"),
        "failure": state.get("failure"),
    }


def ensure_active(state: Dict[str, Any]) -> None:
    if state.get("status") not in ACTIVE_STATUSES:
        raise HumanizeError(
            "loop_not_active",
            "The native RLCR loop is not active",
            {"status": state.get("status"), "phase": state.get("phase")},
            3,
        )


def validate_invariants(loop_dir: Path, state: Dict[str, Any]) -> Path:
    project_root = Path(state["project_root"]).resolve()
    resolved = resolve_project_root(str(project_root))
    if resolved != project_root:
        raise HumanizeError("project_moved", "Project root no longer matches the loop state")
    current_branch = detect_branch(project_root)
    if current_branch != state.get("start_branch"):
        raise HumanizeError(
            "branch_changed",
            "Current branch differs from the branch that started the loop",
            {"expected": state.get("start_branch"), "actual": current_branch},
            3,
        )
    snapshot = loop_dir / "plan.md"
    if not snapshot.is_file() or sha256_file(snapshot) != state.get("plan_snapshot_sha256"):
        raise HumanizeError(
            "plan_snapshot_changed",
            "The loop's immutable plan snapshot was modified or removed",
            {"plan_snapshot": str(snapshot)},
            3,
        )
    if state.get("track_plan_file") and state.get("plan_file"):
        original = project_root / state["plan_file"]
        if not original.is_file() or sha256_file(original) != state.get("original_plan_sha256"):
            raise HumanizeError(
                "tracked_plan_changed",
                "The tracked source plan changed during the loop",
                {"plan_file": state.get("plan_file")},
                3,
            )
    if not ref_exists(project_root, state.get("base_commit", "")):
        raise HumanizeError("base_commit_missing", "The recorded base commit is no longer available", exit_code=4)
    dirty = unmanaged_git_changes(project_root, state.get("ignored_untracked_paths", []))
    if dirty:
        raise HumanizeError(
            "working_tree_dirty",
            "Commit or revert non-Humanize changes before continuing the native loop",
            {"changes": dirty[:50]},
            3,
        )
    return project_root


def create_summary_scaffold(loop_dir: Path, round_number: int, phase: str) -> Path:
    path = loop_dir / ("round-%d-summary.md" % round_number)
    if path.exists():
        return path
    content = """# Humanize Round {round_number} Summary

<!-- Replace this scaffold before requesting review. -->

## Work Completed

- Describe the implementation or fixes completed in this round.

## Files Changed

- List the relevant files.

## Validation

- List every command run and its result.

## Remaining Items

- List unresolved work, or write `None`.

## Round Metadata

- Phase: {phase}
- Round: {round_number}
""".format(round_number=round_number, phase=phase)
    atomic_write_text(path, content)
    return path


def validate_summary(path: Path) -> str:
    if not path.is_file():
        raise HumanizeError("summary_missing", "Round summary file does not exist", {"summary_file": str(path)})
    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise HumanizeError("summary_unreadable", "Round summary is not readable UTF-8 text", {"error": str(exc)})
    if "Replace this scaffold before requesting review" in content:
        raise HumanizeError("summary_incomplete", "Round summary still contains the generated scaffold marker")
    if len(content.strip()) < 80:
        raise HumanizeError("summary_incomplete", "Round summary is too short to support independent review")
    for heading in ("## Work Completed", "## Validation"):
        if heading not in content:
            raise HumanizeError("summary_incomplete", "Round summary is missing a required section", {"section": heading})
    return content


def copy_review_into_loop(loop_dir: Path, review_path: Path, destination_name: str) -> Path:
    resolved = review_path.expanduser().resolve()
    if not resolved.is_file():
        raise HumanizeError("review_missing", "Review result file does not exist", {"review_file": str(resolved)})
    try:
        content = resolved.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise HumanizeError("review_unreadable", "Review result must be readable UTF-8 text", {"error": str(exc)})
    if not content.strip():
        raise HumanizeError("review_empty", "Review result is empty")
    destination = loop_dir / destination_name
    if resolved != destination.resolve():
        atomic_write_text(destination, content)
    return destination


def unique_match(pattern: re.Pattern, content: str, label: str) -> str:
    matches = pattern.findall(content)
    if len(matches) != 1:
        raise HumanizeError(
            "review_contract_invalid",
            "Review must contain exactly one %s marker" % label,
            {"marker_count": len(matches)},
        )
    return matches[0]


def parse_implementation_review(content: str) -> Tuple[str, str]:
    verdict = unique_match(IMPLEMENTATION_MARKER, content, "implementation verdict")
    mainline = unique_match(MAINLINE_MARKER, content, "mainline progress")
    if verdict == "complete" and mainline != "advanced":
        raise HumanizeError(
            "review_contract_invalid",
            "A complete implementation verdict must report advanced mainline progress",
            {"verdict": verdict, "mainline_progress": mainline},
        )
    return verdict, mainline


def parse_code_review(content: str) -> str:
    verdict = unique_match(CODE_MARKER, content, "code review verdict")
    priorities = PRIORITY_MARKER.findall(content)
    if verdict == "changes_required" and not priorities:
        raise HumanizeError(
            "review_contract_invalid",
            "A changes_required code review must contain at least one [P0-9] finding",
        )
    if verdict == "pass" and priorities:
        raise HumanizeError(
            "review_contract_invalid",
            "A passing code review may not contain unresolved [P0-9] findings",
            {"priority_markers": priorities},
        )
    return verdict


def next_round_or_stop(loop_dir: Path, state: Dict[str, Any], reason: str) -> Tuple[str, bool]:
    next_round = int(state["round"]) + 1
    if next_round >= int(state["max_rounds"]):
        state["status"] = "failed"
        state["phase"] = "failed"
        state["failure"] = {
            "code": "max_rounds_exhausted",
            "message": "Maximum native RLCR rounds reached before completion",
            "reason": reason,
            "at": utc_now(),
        }
        state["completed_at"] = utc_now()
        return "report_failed", False
    state["round"] = next_round
    create_summary_scaffold(loop_dir, next_round, state["phase"])
    return "delegate_worker", True


def command_init(args: argparse.Namespace) -> Dict[str, Any]:
    if args.max_rounds < 1:
        raise HumanizeError("invalid_max_rounds", "--max-rounds must be at least 1")
    project_root = resolve_project_root(args.project_root)
    active = active_native_loops(project_root)
    if active:
        raise HumanizeError(
            "loop_already_active",
            "A Codex-native Humanize loop is already active",
            {"loop_dirs": [str(item) for item in active]},
            3,
        )
    start_branch = detect_branch(project_root)
    start_commit = current_commit(project_root)
    base_ref = detect_base_ref(project_root, args.base_ref, start_branch)
    base_commit = resolve_commit(project_root, base_ref)

    plan_file: Optional[Path] = None
    plan_relative: Optional[str] = None
    if args.plan_file:
        plan_file, plan_relative = resolve_plan(project_root, args.plan_file)
        plan_content = plan_file.read_text(encoding="utf-8")
    elif args.review_only:
        plan_content = """# Review-only Humanize Run

## Goal
Review the current branch against the recorded base commit and resolve every blocking finding.

## Acceptance Criteria
- The final independent code review returns `pass`.
- No unresolved `[P0-9]` findings remain.
- Validation evidence is recorded in the round summary.
"""
    else:
        raise HumanizeError("plan_required", "A plan file is required unless --review-only is used")

    plan_initially_untracked = False
    if plan_file is not None and plan_relative is not None:
        tracked = run_git(
            project_root,
            ["ls-files", "--error-unmatch", "--", plan_relative],
            allow_failure=True,
        ).returncode == 0
        plan_initially_untracked = not tracked
    ignored_untracked_paths = [plan_relative] if plan_initially_untracked and plan_relative else []
    dirty = unmanaged_git_changes(project_root, ignored_untracked_paths)
    if dirty:
        raise HumanizeError(
            "working_tree_dirty",
            "Start native RLCR from a clean project tree",
            {"changes": dirty[:50]},
            3,
        )

    if args.loop_dir:
        loop_dir = Path(args.loop_dir).expanduser().resolve()
        relative_to_root(loop_dir, project_root, "Loop directory")
        if loop_dir.exists() and any(loop_dir.iterdir()):
            raise HumanizeError("loop_dir_not_empty", "Requested loop directory is not empty", {"loop_dir": str(loop_dir)})
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S-%f")
        loop_dir = project_root / ".humanize" / "rlcr" / stamp
    loop_dir.mkdir(parents=True, exist_ok=True)

    snapshot = loop_dir / "plan.md"
    atomic_write_text(snapshot, plan_content)
    goal_tracker = loop_dir / "goal-tracker.md"
    atomic_write_text(
        goal_tracker,
        """# Humanize Goal Tracker

## Immutable Goal

Use `plan.md` in this directory as the scope and acceptance source.

## Active Mainline

- Round 0: pending coordinator initialization.

## Blocking Findings

- None recorded.

## Queued Follow-up

- None recorded.

## Verified Outcomes

- None recorded.
""",
    )

    phase = "code_review" if args.review_only else "implementation"
    now = utc_now()
    state: Dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "engine": ENGINE,
        "status": "active",
        "phase": phase,
        "round": 0,
        "max_rounds": args.max_rounds,
        "stall_count": 0,
        "stall_limit": 3,
        "project_root": str(project_root),
        "plan_file": plan_relative,
        "track_plan_file": bool(args.track_plan_file),
        "plan_initially_untracked": plan_initially_untracked,
        "ignored_untracked_paths": ignored_untracked_paths,
        "original_plan_sha256": sha256_file(plan_file) if plan_file else None,
        "plan_snapshot_sha256": sha256_file(snapshot),
        "start_branch": start_branch,
        "start_commit": start_commit,
        "base_ref": base_ref,
        "base_commit": base_commit,
        "last_checkpoint_commit": None,
        "last_checkpoint_round": None,
        "last_summary": None,
        "review_history": [],
        "checkpoint_history": [],
        "failure": None,
        "created_at": now,
        "updated_at": now,
        "completed_at": None,
    }
    create_summary_scaffold(loop_dir, 0, phase)
    save_state(loop_dir, state, "initialized", {"review_only": bool(args.review_only)})
    next_action = "delegate_code_reviewer" if args.review_only else "delegate_worker"
    return public_state(loop_dir, state, "initialized", next_action)


def command_status(args: argparse.Namespace) -> Dict[str, Any]:
    loop_dir = Path(args.loop_dir).expanduser().resolve()
    state = load_state(loop_dir)
    mapping = {
        "implementation": "delegate_worker",
        "fix": "delegate_worker",
        "code_review": "delegate_code_reviewer",
        "complete": "report_complete",
        "failed": "report_failed",
        "cancelled": "report_cancelled",
        "blocked": "report_blocked",
    }
    return public_state(loop_dir, state, "status", mapping.get(str(state.get("phase")), "inspect_state"))


def command_validate(args: argparse.Namespace) -> Dict[str, Any]:
    loop_dir = Path(args.loop_dir).expanduser().resolve()
    state = load_state(loop_dir)
    ensure_active(state)
    validate_invariants(loop_dir, state)
    return public_state(loop_dir, state, "validated", "continue")


def command_checkpoint(args: argparse.Namespace) -> Dict[str, Any]:
    loop_dir = Path(args.loop_dir).expanduser().resolve()
    state = load_state(loop_dir)
    ensure_active(state)
    project_root = validate_invariants(loop_dir, state)
    phase = state.get("phase")
    if phase not in ("implementation", "fix"):
        raise HumanizeError(
            "invalid_phase", "A worker checkpoint is only valid during implementation or fix phases", {"phase": phase}, 3
        )
    expected_summary = loop_dir / ("round-%d-summary.md" % int(state["round"]))
    supplied = Path(args.summary_file).expanduser().resolve() if args.summary_file else expected_summary
    if supplied != expected_summary.resolve():
        raise HumanizeError(
            "unexpected_summary_path",
            "Summary must use the loop's round-specific path",
            {"expected": str(expected_summary), "actual": str(supplied)},
        )
    summary = validate_summary(expected_summary)
    head = current_commit(project_root)
    previous = state.get("last_checkpoint_commit") or state.get("start_commit")
    if head == previous and not args.allow_no_new_commit:
        raise HumanizeError(
            "checkpoint_not_advanced",
            "The worker did not create a new commit for this round",
            {"head": head, "previous_checkpoint": previous},
            3,
        )
    if previous and run_git(
        project_root,
        ["merge-base", "--is-ancestor", str(previous), head],
        allow_failure=True,
    ).returncode != 0:
        raise HumanizeError(
            "history_rewritten",
            "The current commit is not a descendant of the previous native checkpoint",
            {"head": head, "previous_checkpoint": previous},
            3,
        )
    checkpoint = {
        "round": state["round"],
        "phase": phase,
        "commit": head,
        "summary_file": expected_summary.name,
        "summary_sha256": sha256_bytes(summary.encode("utf-8")),
        "at": utc_now(),
    }
    state["last_checkpoint_commit"] = head
    state["last_checkpoint_round"] = state["round"]
    state["last_summary"] = expected_summary.name
    state["checkpoint_history"].append(checkpoint)
    save_state(loop_dir, state, "checkpoint_recorded", checkpoint)
    next_action = "delegate_implementation_reviewer" if phase == "implementation" else "delegate_code_reviewer"
    return public_state(loop_dir, state, "checkpoint_recorded", next_action)


def command_record_review(args: argparse.Namespace) -> Dict[str, Any]:
    loop_dir = Path(args.loop_dir).expanduser().resolve()
    state = load_state(loop_dir)
    ensure_active(state)
    validate_invariants(loop_dir, state)
    round_number = int(state["round"])
    source = Path(args.review_file).expanduser().resolve()

    if args.kind == "implementation":
        if state.get("phase") != "implementation":
            raise HumanizeError(
                "invalid_phase", "Implementation review is not valid in the current phase", {"phase": state.get("phase")}, 3
            )
        if state.get("last_checkpoint_round") != round_number:
            raise HumanizeError("checkpoint_required", "Record a valid worker checkpoint before implementation review", exit_code=3)
        destination = copy_review_into_loop(
            loop_dir, source, "round-%d-implementation-review.md" % round_number
        )
        content = destination.read_text(encoding="utf-8")
        verdict, mainline = parse_implementation_review(content)
        history = {
            "round": round_number,
            "kind": "implementation",
            "verdict": verdict,
            "mainline_progress": mainline,
            "file": destination.name,
            "sha256": sha256_file(destination),
            "at": utc_now(),
        }
        state["review_history"].append(history)
        if mainline == "advanced":
            state["stall_count"] = 0
        else:
            state["stall_count"] = int(state.get("stall_count", 0)) + 1

        if verdict == "blocked":
            state["status"] = "blocked"
            state["phase"] = "blocked"
            state["failure"] = {
                "code": "review_blocked",
                "message": "The implementation reviewer could not complete an independent review",
                "at": utc_now(),
            }
            state["completed_at"] = utc_now()
            next_action = "report_blocked"
        elif verdict == "complete":
            state["phase"] = "code_review"
            next_action = "delegate_code_reviewer"
        elif int(state["stall_count"]) >= int(state.get("stall_limit", 3)):
            state["status"] = "blocked"
            state["phase"] = "blocked"
            state["failure"] = {
                "code": "mainline_stalled",
                "message": "Mainline progress stalled or regressed for three consecutive reviews",
                "at": utc_now(),
            }
            state["completed_at"] = utc_now()
            next_action = "report_blocked"
        else:
            state["phase"] = "implementation"
            next_action, _ = next_round_or_stop(loop_dir, state, "implementation review requested another round")
        save_state(loop_dir, state, "review_recorded", history)
        return public_state(loop_dir, state, "review_recorded", next_action)

    if state.get("phase") not in ("code_review", "fix"):
        raise HumanizeError(
            "invalid_phase", "Code review is not valid in the current phase", {"phase": state.get("phase")}, 3
        )
    if state.get("phase") == "fix" and state.get("last_checkpoint_round") != round_number:
        raise HumanizeError("checkpoint_required", "Record a valid fix checkpoint before code review", exit_code=3)
    destination = copy_review_into_loop(loop_dir, source, "round-%d-code-review.md" % round_number)
    content = destination.read_text(encoding="utf-8")
    verdict = parse_code_review(content)
    history = {
        "round": round_number,
        "kind": "code",
        "verdict": verdict,
        "file": destination.name,
        "sha256": sha256_file(destination),
        "at": utc_now(),
    }
    state["review_history"].append(history)
    if verdict == "pass":
        state["status"] = "complete"
        state["phase"] = "complete"
        state["failure"] = None
        state["completed_at"] = utc_now()
        next_action = "report_complete"
    elif verdict == "blocked":
        state["status"] = "blocked"
        state["phase"] = "blocked"
        state["failure"] = {
            "code": "review_blocked",
            "message": "The code reviewer could not complete an independent review",
            "at": utc_now(),
        }
        state["completed_at"] = utc_now()
        next_action = "report_blocked"
    else:
        state["phase"] = "fix"
        next_action, advanced = next_round_or_stop(loop_dir, state, "code review found blocking issues")
        if advanced:
            # The new round must be checkpointed after the worker fixes the findings.
            state["last_checkpoint_round"] = None
    save_state(loop_dir, state, "review_recorded", history)
    return public_state(loop_dir, state, "review_recorded", next_action)


def command_fail(args: argparse.Namespace) -> Dict[str, Any]:
    loop_dir = Path(args.loop_dir).expanduser().resolve()
    state = load_state(loop_dir)
    if state.get("status") in TERMINAL_STATUSES:
        raise HumanizeError(
            "loop_terminal", "A terminal loop cannot be failed or cancelled again", {"status": state.get("status")}, 3
        )
    status = "cancelled" if args.code in ("cancelled", "interrupted") else "failed"
    if args.code in ("agent_unavailable", "permission_denied"):
        status = "blocked"
    state["status"] = status
    state["phase"] = status
    state["failure"] = {"code": args.code, "message": args.message, "at": utc_now()}
    state["completed_at"] = utc_now() if status in TERMINAL_STATUSES else None
    save_state(loop_dir, state, "loop_%s" % status, state["failure"])
    return public_state(loop_dir, state, "loop_%s" % status, "report_%s" % status)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Deterministic state and contract validation for Humanize Codex-native RLCR"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    init = subparsers.add_parser("init", help="Create a new native RLCR loop")
    init.add_argument("--project-root")
    init.add_argument("--plan-file")
    init.add_argument("--review-only", action="store_true")
    init.add_argument("--track-plan-file", action="store_true")
    init.add_argument("--max-rounds", type=int, default=42)
    init.add_argument("--base-ref")
    init.add_argument("--loop-dir")
    init.set_defaults(handler=command_init)

    status = subparsers.add_parser("status", help="Read current loop state")
    status.add_argument("--loop-dir", required=True)
    status.set_defaults(handler=command_status)

    validate = subparsers.add_parser("validate", help="Validate branch and plan invariants")
    validate.add_argument("--loop-dir", required=True)
    validate.set_defaults(handler=command_validate)

    checkpoint = subparsers.add_parser("checkpoint", help="Validate and record a worker round checkpoint")
    checkpoint.add_argument("--loop-dir", required=True)
    checkpoint.add_argument("--summary-file")
    checkpoint.add_argument("--allow-no-new-commit", action="store_true")
    checkpoint.set_defaults(handler=command_checkpoint)

    review = subparsers.add_parser("record-review", help="Parse and persist a native reviewer result")
    review.add_argument("--loop-dir", required=True)
    review.add_argument("--kind", choices=("implementation", "code"), required=True)
    review.add_argument("--review-file", required=True)
    review.set_defaults(handler=command_record_review)

    fail = subparsers.add_parser("fail", help="Persist cancellation, permission, or agent failures")
    fail.add_argument("--loop-dir", required=True)
    fail.add_argument(
        "--code",
        required=True,
        choices=(
            "agent_unavailable",
            "permission_denied",
            "cancelled",
            "interrupted",
            "validation_failed",
            "agent_failed",
        ),
    )
    fail.add_argument("--message", required=True)
    fail.set_defaults(handler=command_fail)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            project_root = resolve_project_root(args.project_root)
            lock_path = project_root / ".humanize" / "rlcr" / ".native-init.lock"
        else:
            loop_dir = Path(args.loop_dir).expanduser().resolve()
            if not loop_dir.is_dir():
                raise HumanizeError("state_not_found", "Native RLCR loop directory was not found", {"loop_dir": str(loop_dir)})
            lock_path = loop_dir / ".native-state.lock"
        with exclusive_lock(lock_path):
            payload = args.handler(args)
    except HumanizeError as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": {"code": exc.code, "message": exc.message, "details": exc.details},
                },
                sort_keys=True,
            )
        )
        return exc.exit_code
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": {
                        "code": "internal_error",
                        "message": "Native RLCR runtime encountered an internal error",
                        "details": {"type": type(exc).__name__, "error": str(exc)},
                    },
                },
                sort_keys=True,
            )
        )
        return 70
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
