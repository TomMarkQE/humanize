#!/usr/bin/env python3
"""Shared deterministic helpers for Codex Humanizer RLCR.

This module never invokes a model. The live Codex root thread owns native
subagent orchestration; this runtime only validates repository invariants,
serializes state transitions, and persists artifacts atomically.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
from typing import Any, Dict, Iterable, Iterator, List, Optional, Sequence, Tuple

try:
    import fcntl  # type: ignore
except ImportError:  # pragma: no cover - supported Codex hosts are Unix-like.
    fcntl = None

SCHEMA_VERSION = 2
ORCHESTRATION_MODE = "codex_humanizer_native"
STATE_ROOT_NAME = ".codex-humanizer"
STATE_BODY = """# Codex Humanizer Native RLCR State

This file is owned by `native-rlcr.py`. Do not edit it manually.
The live Codex root thread coordinates native worker, research, and reviewer
children; this file records deterministic checkpoints only.
"""

ACTIVE_STATE_NAMES = ("state.md", "finalize-state.md")
TERMINAL_STATE_NAMES = (
    "complete-state.md",
    "blocked-state.md",
    "failed-state.md",
    "cancelled-state.md",
)

WORKER_SECTIONS = (
    "## What Was Implemented",
    "## Files Changed",
    "## Validation",
    "## Remaining Items",
)
RESEARCH_SECTIONS = (
    "## Findings",
    "## Evidence",
    "## Implications",
    "## Unknowns",
)
FINALIZE_SECTIONS = (
    "## Simplifications",
    "## Validation",
    "## Remaining Risks",
)
IMPLEMENTATION_REVIEW_SECTIONS = (
    "## Verified Evidence",
    "## Acceptance-Criteria Status",
    "## Blocking Issues",
    "## Queued Follow-up",
    "## Required Next Objective",
)
CODE_REVIEW_SECTIONS = (
    "## Findings",
    "## Validation Gaps",
    "## Non-blocking Notes",
)
CONTRACT_LABELS = (
    "Mainline Objective:",
    "Target ACs:",
    "Blocking Side Issues In Scope:",
    "Queued Side Issues Out of Scope:",
    "Success Criteria:",
)

IMPL_VERDICTS = {"CONTINUE", "COMPLETE", "BLOCKED"}
PROGRESS_VERDICTS = {"ADVANCED", "STALLED", "REGRESSED", "COMPLETE"}
CODE_VERDICTS = {"PASS", "CHANGES_REQUESTED", "BLOCKED"}
READ_ONLY_STAGES = {"research", "implementation-review", "code-review"}
WORKER_PHASES = {"implementation", "code-fix"}


class HumanizeError(RuntimeError):
    """A deterministic workflow or repository invariant was violated."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    return sha256_bytes(path.read_bytes())


def sha256_text(text: str) -> str:
    return sha256_bytes(text.encode("utf-8"))


def atomic_write(path: pathlib.Path, text: str, mode: Optional[int] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    tmp_path = pathlib.Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def atomic_copy_text(source: pathlib.Path, destination: pathlib.Path) -> None:
    atomic_write(destination, source.read_text(encoding="utf-8"))


def run_git(repo: pathlib.Path, args: Sequence[str], *, check: bool = True) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        raise HumanizeError(f"git {' '.join(args)} failed: {detail}")
    return proc.stdout.strip()


def resolve_repo(repo_arg: Optional[str]) -> pathlib.Path:
    cwd = pathlib.Path(repo_arg or os.getcwd()).expanduser().resolve()
    root = run_git(cwd, ["rev-parse", "--show-toplevel"])
    return pathlib.Path(root).resolve()


def current_branch(repo: pathlib.Path) -> str:
    branch = run_git(repo, ["symbolic-ref", "--quiet", "--short", "HEAD"], check=False)
    if not branch:
        raise HumanizeError("RLCR requires a named branch; detached HEAD is not supported")
    return branch


def head_commit(repo: pathlib.Path) -> str:
    return run_git(repo, ["rev-parse", "HEAD"])


def git_object_commit(repo: pathlib.Path, ref: str) -> str:
    commit = run_git(repo, ["rev-parse", "--verify", f"{ref}^{{commit}}"], check=False)
    if not commit:
        raise HumanizeError(f"base ref does not resolve to a commit: {ref}")
    return commit


def is_ancestor(repo: pathlib.Path, ancestor: str, descendant: str) -> bool:
    proc = subprocess.run(
        ["git", "-C", str(repo), "merge-base", "--is-ancestor", ancestor, descendant],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc.returncode == 0


def detect_base_ref(repo: pathlib.Path, explicit: Optional[str]) -> str:
    if explicit:
        git_object_commit(repo, explicit)
        return explicit

    remote_head = run_git(
        repo,
        ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
        check=False,
    )
    if remote_head.startswith("origin/"):
        candidate = remote_head.split("/", 1)[1]
        if run_git(repo, ["rev-parse", "--verify", f"{candidate}^{{commit}}"], check=False):
            return candidate

    for candidate in ("main", "master"):
        if run_git(repo, ["rev-parse", "--verify", f"{candidate}^{{commit}}"], check=False):
            return candidate
    return current_branch(repo)


def normalize_status_path(raw: str) -> str:
    raw = raw.strip()
    if " -> " in raw:
        raw = raw.split(" -> ", 1)[1]
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        try:
            return bytes(raw[1:-1], "utf-8").decode("unicode_escape")
        except UnicodeDecodeError:
            return raw[1:-1]
    return raw


def relevant_status(repo: pathlib.Path) -> List[str]:
    output = run_git(repo, ["status", "--porcelain=v1", "--untracked-files=all"])
    rows: List[str] = []
    ignored_prefix = f"{STATE_ROOT_NAME}/"
    for line in output.splitlines():
        if not line:
            continue
        raw_path = line[3:] if len(line) >= 4 else line
        path = normalize_status_path(raw_path)
        if path == STATE_ROOT_NAME or path.startswith(ignored_prefix):
            continue
        rows.append(line)
    return rows


def status_fingerprint(repo: pathlib.Path) -> str:
    return sha256_text("\n".join(relevant_status(repo)) + "\n")


def require_clean(repo: pathlib.Path) -> None:
    rows = relevant_status(repo)
    if rows:
        formatted = "\n".join(rows[:30])
        raise HumanizeError(
            f"repository must be clean outside {STATE_ROOT_NAME} before this transition:\n{formatted}"
        )


def resolve_input_file(repo: pathlib.Path, value: str, label: str) -> pathlib.Path:
    candidate = pathlib.Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = repo / candidate
    candidate = candidate.resolve()
    if not candidate.is_file():
        raise HumanizeError(f"{label} file not found: {candidate}")
    return candidate


def display_repo_path(repo: pathlib.Path, path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(repo).as_posix()
    except ValueError:
        return str(path.resolve())


def parse_scalar(raw: str) -> Any:
    value = raw.strip()
    if value == "":
        return ""
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "null":
        return None
    if re.fullmatch(r"-?[0-9]+", value):
        return int(value)
    if value.startswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError as exc:
            raise HumanizeError(f"invalid JSON string in state: {value}: {exc}") from exc
    return value


def encode_scalar(value: Any) -> str:
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


STATE_KEY_ORDER = (
    "schema_version",
    "orchestration_mode",
    "status",
    "phase",
    "worker_mode",
    "current_round",
    "max_rounds",
    "plan_file",
    "plan_tracked",
    "plan_sha256",
    "plan_snapshot_sha256",
    "repo_root",
    "start_branch",
    "base_ref",
    "base_commit",
    "head_commit",
    "review_started",
    "mainline_stall_count",
    "last_mainline_verdict",
    "goal_immutable_sha256",
    "active_stage",
    "guard_head",
    "guard_status_sha256",
    "worker_start_head",
    "last_worker_changed",
    "started_at",
    "updated_at",
    "terminal_reason",
)


def render_state(state: Dict[str, Any]) -> str:
    keys: List[str] = list(STATE_KEY_ORDER)
    keys.extend(sorted(key for key in state if key not in STATE_KEY_ORDER))
    frontmatter = ["---"]
    for key in keys:
        if key in state:
            frontmatter.append(f"{key}: {encode_scalar(state[key])}")
    frontmatter.append("---")
    return "\n".join(frontmatter) + "\n" + STATE_BODY


def parse_state(path: pathlib.Path) -> Dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise HumanizeError(f"state file is missing frontmatter: {path}")
    try:
        end = lines.index("---", 1)
    except ValueError as exc:
        raise HumanizeError(f"state file has unterminated frontmatter: {path}") from exc
    state: Dict[str, Any] = {}
    for line in lines[1:end]:
        if not line.strip():
            continue
        if ":" not in line:
            raise HumanizeError(f"invalid state line: {line}")
        key, raw = line.split(":", 1)
        state[key.strip()] = parse_scalar(raw)
    return state


def state_path(run_dir: pathlib.Path) -> pathlib.Path:
    for name in ACTIVE_STATE_NAMES:
        candidate = run_dir / name
        if candidate.is_file():
            return candidate
    raise HumanizeError(f"no active Codex Humanizer RLCR state found in {run_dir}")


def write_state(path: pathlib.Path, state: Dict[str, Any]) -> None:
    state["updated_at"] = utc_now()
    atomic_write(path, render_state(state))
