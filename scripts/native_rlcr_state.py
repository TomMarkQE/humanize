#!/usr/bin/env python3
"""State persistence and invariant checks for Codex Humanizer RLCR."""

from native_rlcr_common import *  # noqa: F401,F403 - internal sibling runtime surface


@contextlib.contextmanager
def run_lock(run_dir: pathlib.Path) -> Iterator[None]:
    run_dir.mkdir(parents=True, exist_ok=True)
    lock_path = run_dir / ".state.lock"
    with lock_path.open("a+") as handle:
        if fcntl is not None:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if fcntl is not None:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def append_event(run_dir: pathlib.Path, event: str, state: Dict[str, Any], **details: Any) -> None:
    payload = {
        "time": utc_now(),
        "event": event,
        "round": state.get("current_round"),
        "phase": state.get("phase"),
        "status": state.get("status"),
        "details": details,
    }
    event_path = run_dir / "events.jsonl"
    with event_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def output_json(payload: Dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))


def read_text(path: pathlib.Path, label: str) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise HumanizeError(f"{label} must be UTF-8: {path}") from exc
    if not text.strip():
        raise HumanizeError(f"{label} is empty: {path}")
    return text


def require_sections(text: str, sections: Iterable[str], label: str) -> None:
    missing = [section for section in sections if section not in text]
    if missing:
        raise HumanizeError(f"{label} is missing required sections: {', '.join(missing)}")


def extract_plan_section(text: str, headings: Sequence[str]) -> str:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.strip() in headings:
            result: List[str] = []
            for candidate in lines[index + 1 :]:
                if candidate.startswith("## "):
                    break
                result.append(candidate)
            value = "\n".join(result).strip()
            if value:
                return value
    return ""


def create_goal_tracker(plan_text: str) -> str:
    goal = extract_plan_section(plan_text, ("## Goal Description", "## Goal", "## Objective", "## Purpose"))
    acceptance = extract_plan_section(plan_text, ("## Acceptance Criteria", "## Criteria", "## Requirements"))
    if not goal:
        non_heading = [line.strip() for line in plan_text.splitlines() if line.strip() and not line.startswith("#")]
        goal = "\n".join(non_heading[:5]) or "Execute the supplied implementation plan."
    if not acceptance:
        acceptance = "- Preserve the plan scope and produce verifiable implementation evidence."
    return f"""# Goal Tracker

## IMMUTABLE SECTION

### Ultimate Goal

{goal}

### Acceptance Criteria

{acceptance}

---

## MUTABLE SECTION

### Plan Version: 1 (Updated: Round 0)

#### Plan Evolution Log
| Round | Change | Reason | Impact on AC |
|-------|--------|--------|--------------|
| 0 | Initial native RLCR plan | Run started | None |

#### Active Tasks
| Task | Target AC | Status | Owner | Evidence |
|------|-----------|--------|-------|----------|
| Define and execute the current mainline objective | Plan ACs | pending | worker | pending |

### Blocking Side Issues
| Issue | Discovered Round | Blocking AC | Resolution Path |
|-------|-----------------|-------------|-----------------|

### Queued Side Issues
| Issue | Discovered Round | Why Not Blocking | Revisit Trigger |
|-------|-----------------|------------------|-----------------|

### Completed and Verified
| AC | Task | Completed Round | Verified Round | Evidence |
|----|------|-----------------|----------------|----------|

### Explicitly Deferred
| Task | Original AC | Deferred Since | Justification | When to Reconsider |
|------|-------------|----------------|---------------|-------------------|
"""


def goal_immutable_text(goal_text: str) -> str:
    match = re.search(r"(?ms)^## IMMUTABLE SECTION\s*$\n(.*?)^---\s*$", goal_text)
    if not match:
        raise HumanizeError("goal tracker is missing the immutable section delimiter")
    return match.group(1).strip() + "\n"


def state_base_dir(repo: pathlib.Path) -> pathlib.Path:
    return repo / STATE_ROOT_NAME / "rlcr"


def ensure_no_active_run(repo: pathlib.Path) -> None:
    base = state_base_dir(repo)
    if not base.is_dir():
        return
    active: List[str] = []
    for child in base.iterdir():
        if child.is_dir() and any((child / name).is_file() for name in ACTIVE_STATE_NAMES):
            active.append(str(child))
    if active:
        raise HumanizeError("an active RLCR run already exists: " + ", ".join(sorted(active)))


def validate_plan_text(text: str, label: str) -> None:
    if not text.strip():
        raise HumanizeError(f"{label} is empty")
    if len(text.splitlines()) < 5:
        raise HumanizeError(f"{label} must contain at least five lines")
    required = ("## Goal Description", "## Acceptance Criteria")
    require_sections(text, required, label)


def terminalize(run_dir: pathlib.Path, active_path: pathlib.Path, state: Dict[str, Any], status: str, reason: str) -> pathlib.Path:
    if status not in {"complete", "blocked", "failed", "cancelled"}:
        raise HumanizeError(f"invalid terminal status: {status}")
    state["status"] = status
    state["phase"] = status
    state["active_stage"] = ""
    state["terminal_reason"] = reason
    write_state(active_path, state)
    target = run_dir / f"{status}-state.md"
    os.replace(active_path, target)
    append_event(run_dir, status, state, reason=reason)
    return target


def validate_active(run_dir: pathlib.Path, state: Dict[str, Any]) -> pathlib.Path:
    if state.get("schema_version") != SCHEMA_VERSION:
        raise HumanizeError("unsupported native RLCR state schema")
    if state.get("orchestration_mode") != ORCHESTRATION_MODE:
        raise HumanizeError("state is not a Codex Humanizer native-subagent RLCR run")
    if state.get("status") != "active":
        raise HumanizeError(f"run is not active: {state.get('status')}")

    repo = pathlib.Path(str(state.get("repo_root", ""))).resolve()
    run_git(repo, ["rev-parse", "--show-toplevel"])
    if current_branch(repo) != state.get("start_branch"):
        raise HumanizeError(
            f"branch changed during RLCR: expected {state.get('start_branch')}, got {current_branch(repo)}"
        )

    snapshot = run_dir / "plan.md"
    if not snapshot.is_file() or sha256_file(snapshot) != state.get("plan_snapshot_sha256"):
        raise HumanizeError("run plan snapshot changed after initialization")

    if state.get("plan_tracked"):
        source = pathlib.Path(str(state.get("plan_file", "")))
        if not source.is_absolute():
            source = repo / source
        if not source.is_file() or sha256_file(source) != state.get("plan_sha256"):
            raise HumanizeError("tracked source plan changed after initialization")

    goal = run_dir / "goal-tracker.md"
    goal_text = read_text(goal, "goal tracker")
    if sha256_text(goal_immutable_text(goal_text)) != state.get("goal_immutable_sha256"):
        raise HumanizeError("goal tracker immutable section changed")

    base_commit = str(state.get("base_commit", ""))
    git_object_commit(repo, base_commit)
    current = head_commit(repo)
    if not is_ancestor(repo, base_commit, current):
        raise HumanizeError("fixed base commit is no longer an ancestor of HEAD")
    return repo


def manifest(run_dir: pathlib.Path, state: Dict[str, Any], state_file: pathlib.Path) -> Dict[str, Any]:
    round_number = int(state.get("current_round", 0))
    return {
        "run_dir": str(run_dir),
        "state_file": str(state_file),
        "status": state.get("status"),
        "phase": state.get("phase"),
        "round": round_number,
        "max_rounds": state.get("max_rounds"),
        "worker_mode": state.get("worker_mode"),
        "repo_root": state.get("repo_root"),
        "start_branch": state.get("start_branch"),
        "base_ref": state.get("base_ref"),
        "base_commit": state.get("base_commit"),
        "head_commit": state.get("head_commit"),
        "plan": str(run_dir / "plan.md"),
        "goal_tracker": str(run_dir / "goal-tracker.md"),
        "contract": str(run_dir / f"round-{round_number}-contract.md"),
        "worker_summary": str(run_dir / f"round-{round_number}-summary.md"),
        "research_result": str(run_dir / f"round-{round_number}-research.md"),
        "implementation_review": str(run_dir / f"round-{round_number}-implementation-review.md"),
        "code_review": str(run_dir / f"round-{round_number}-code-review.md"),
        "active_stage": state.get("active_stage"),
    }


def load_run(run_dir_arg: str) -> Tuple[pathlib.Path, pathlib.Path, Dict[str, Any]]:
    run_dir = pathlib.Path(run_dir_arg).expanduser().resolve()
    active = state_path(run_dir)
    state = parse_state(active)
    return run_dir, active, state
