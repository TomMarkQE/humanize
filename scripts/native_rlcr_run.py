#!/usr/bin/env python3
"""Run initialization, stage preparation, and worker checkpoints."""

from native_rlcr_state import *  # noqa: F401,F403 - internal sibling runtime surface


def command_start(args: argparse.Namespace) -> None:
    repo = resolve_repo(args.repo)
    ensure_no_active_run(repo)
    require_clean(repo)
    branch = current_branch(repo)
    base_ref = detect_base_ref(repo, args.base_ref)
    base_commit = git_object_commit(repo, base_ref)
    current = head_commit(repo)
    if not is_ancestor(repo, base_commit, current):
        raise HumanizeError(f"base ref {base_ref} is not an ancestor of current HEAD")

    plan_path: Optional[pathlib.Path] = None
    if args.plan:
        plan_path = resolve_input_file(repo, args.plan, "plan")
        plan_text = read_text(plan_path, "plan")
        validate_plan_text(plan_text, "plan")
    elif args.review_only:
        plan_text = """# Review-only RLCR

## Goal Description
Review the current branch against the fixed base and resolve blocking findings.

## Acceptance Criteria
- No unresolved `[P0-9]` findings remain.
- Validation evidence remains current.
"""
    else:
        raise HumanizeError("--plan is required unless --review-only is used")

    if args.track_plan_file:
        if plan_path is None:
            raise HumanizeError("--track-plan-file requires --plan")
        try:
            relative = plan_path.relative_to(repo).as_posix()
        except ValueError as exc:
            raise HumanizeError("a tracked plan must be inside the repository") from exc
        tracked = subprocess.run(
            ["git", "-C", str(repo), "ls-files", "--error-unmatch", "--", relative],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
        if not tracked:
            raise HumanizeError(f"tracked plan is not in git: {relative}")
        if run_git(repo, ["status", "--porcelain=v1", "--", relative]):
            raise HumanizeError("tracked plan must be clean at run start")

    base_dir = state_base_dir(repo)
    base_dir.mkdir(parents=True, exist_ok=True)
    timestamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    run_dir = base_dir / timestamp
    suffix = 1
    while run_dir.exists():
        run_dir = base_dir / f"{timestamp}-{suffix}"
        suffix += 1
    run_dir.mkdir(parents=True)

    normalized_plan = plan_text if plan_text.endswith("\n") else plan_text + "\n"
    atomic_write(run_dir / "plan.md", normalized_plan)
    goal_text = create_goal_tracker(plan_text)
    atomic_write(run_dir / "goal-tracker.md", goal_text)

    source_label = display_repo_path(repo, plan_path) if plan_path else str(run_dir / "plan.md")
    initial_phase = "code-review" if args.review_only else "implementation"
    state: Dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "orchestration_mode": ORCHESTRATION_MODE,
        "status": "active",
        "phase": initial_phase,
        "worker_mode": "code-fix" if args.review_only else "implementation",
        "current_round": 0,
        "max_rounds": args.max_rounds,
        "plan_file": source_label,
        "plan_tracked": bool(args.track_plan_file),
        "plan_sha256": sha256_file(plan_path) if plan_path else sha256_text(normalized_plan),
        "plan_snapshot_sha256": sha256_file(run_dir / "plan.md"),
        "repo_root": str(repo),
        "start_branch": branch,
        "base_ref": base_ref,
        "base_commit": base_commit,
        "head_commit": current,
        "review_started": bool(args.review_only),
        "mainline_stall_count": 0,
        "last_mainline_verdict": "unknown",
        "goal_immutable_sha256": sha256_text(goal_immutable_text(goal_text)),
        "active_stage": "",
        "guard_head": "",
        "guard_status_sha256": "",
        "worker_start_head": "",
        "last_worker_changed": False,
        "started_at": utc_now(),
        "updated_at": utc_now(),
    }
    state_file = run_dir / "state.md"
    write_state(state_file, state)
    append_event(run_dir, "run_started", state, base_ref=base_ref, review_only=args.review_only)
    output_json(manifest(run_dir, state, state_file))


def command_status(args: argparse.Namespace) -> None:
    run_dir, active, state = load_run(args.run_dir)
    validate_active(run_dir, state)
    output_json(manifest(run_dir, state, active))


def validate_contract(path: pathlib.Path) -> str:
    text = read_text(path, "round contract")
    missing = [label for label in CONTRACT_LABELS if label not in text]
    if missing:
        raise HumanizeError("round contract is missing required labels: " + ", ".join(missing))
    return text


def command_prepare_stage(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        stage = args.stage
        if state.get("active_stage"):
            raise HumanizeError(f"another stage is already active: {state.get('active_stage')}")
        phase = str(state.get("phase"))

        if stage == "worker":
            if phase not in WORKER_PHASES:
                raise HumanizeError(f"worker is not valid in phase {phase}")
            require_clean(repo)
            if phase == "implementation":
                if not args.contract:
                    raise HumanizeError("implementation worker requires --contract")
                contract_path = resolve_input_file(repo, args.contract, "contract")
                validate_contract(contract_path)
                atomic_copy_text(contract_path, run_dir / f"round-{state['current_round']}-contract.md")
            state["worker_start_head"] = head_commit(repo)
        elif stage == "research":
            if phase not in {"implementation", "code-fix"}:
                raise HumanizeError(f"research is not valid in phase {phase}")
            require_clean(repo)
            state["guard_head"] = head_commit(repo)
            state["guard_status_sha256"] = status_fingerprint(repo)
        elif stage == "implementation-review":
            if phase != "implementation-review":
                raise HumanizeError(f"implementation review is not valid in phase {phase}")
            require_clean(repo)
            read_text(run_dir / f"round-{state['current_round']}-summary.md", "worker summary")
            state["guard_head"] = head_commit(repo)
            state["guard_status_sha256"] = status_fingerprint(repo)
        elif stage == "code-review":
            if phase != "code-review":
                raise HumanizeError(f"code review is not valid in phase {phase}")
            require_clean(repo)
            current = head_commit(repo)
            if not is_ancestor(repo, str(state["base_commit"]), current):
                raise HumanizeError("code review base is not an ancestor of HEAD")
            state["guard_head"] = current
            state["guard_status_sha256"] = status_fingerprint(repo)
        elif stage == "finalize":
            if phase != "finalize":
                raise HumanizeError(f"finalize worker is not valid in phase {phase}")
            require_clean(repo)
            state["worker_start_head"] = head_commit(repo)
        else:
            raise HumanizeError(f"unsupported stage: {stage}")

        state["active_stage"] = stage
        write_state(active, state)
        append_event(run_dir, "stage_prepared", state, stage=stage)
        output_json(manifest(run_dir, state, active))


def verify_read_only_guard(repo: pathlib.Path, state: Dict[str, Any]) -> None:
    expected_head = str(state.get("guard_head", ""))
    expected_status = str(state.get("guard_status_sha256", ""))
    actual_head = head_commit(repo)
    actual_status = status_fingerprint(repo)
    if actual_head != expected_head or actual_status != expected_status:
        raise HumanizeError(
            "read-only child changed repository state; "
            f"expected HEAD/status {expected_head}/{expected_status}, got {actual_head}/{actual_status}"
        )


def command_record_research(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        if state.get("active_stage") != "research":
            raise HumanizeError("no research stage is active")
        verify_read_only_guard(repo, state)
        result = resolve_input_file(repo, args.result, "research result")
        text = read_text(result, "research result")
        require_sections(text, RESEARCH_SECTIONS, "research result")
        destination = run_dir / f"round-{state['current_round']}-research.md"
        atomic_copy_text(result, destination)
        state["active_stage"] = ""
        state["guard_head"] = ""
        state["guard_status_sha256"] = ""
        write_state(active, state)
        append_event(run_dir, "research_recorded", state, result=str(destination))
        output_json(manifest(run_dir, state, active))


def command_record_worker(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        if state.get("active_stage") != "worker":
            raise HumanizeError("no worker stage is active")
        phase = str(state.get("phase"))
        if phase not in WORKER_PHASES:
            raise HumanizeError(f"worker result is not valid in phase {phase}")
        require_clean(repo)
        start_head = str(state.get("worker_start_head", ""))
        current = head_commit(repo)
        if start_head and not is_ancestor(repo, start_head, current):
            raise HumanizeError("worker rewrote or abandoned the checkpoint history")
        result = resolve_input_file(repo, args.result, "worker result")
        text = read_text(result, "worker result")
        require_sections(text, WORKER_SECTIONS, "worker result")
        destination = run_dir / f"round-{state['current_round']}-summary.md"
        atomic_copy_text(result, destination)
        changed = current != start_head
        state["head_commit"] = current
        state["last_worker_changed"] = changed
        state["active_stage"] = ""
        state["worker_start_head"] = ""
        state["phase"] = "implementation-review" if phase == "implementation" else "code-review"
        write_state(active, state)
        append_event(run_dir, "worker_recorded", state, changed=changed, result=str(destination))
        output_json(manifest(run_dir, state, active))
