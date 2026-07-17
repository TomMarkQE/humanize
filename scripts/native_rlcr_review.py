#!/usr/bin/env python3
"""Independent review, goal-tracker, and terminal transitions."""

from native_rlcr_run import *  # noqa: F401,F403 - internal sibling runtime surface


def extract_field(text: str, label: str, allowed: Iterable[str]) -> str:
    match = re.search(rf"(?mi)^{re.escape(label)}\s*:\s*([A-Z_]+)\s*$", text)
    if not match:
        raise HumanizeError(f"result is missing `{label}: ...`")
    value = match.group(1).upper()
    allowed_set = set(allowed)
    if value not in allowed_set:
        raise HumanizeError(f"invalid {label} value {value}; expected one of {sorted(allowed_set)}")
    return value


def final_marker(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        raise HumanizeError("result has no final marker")
    return lines[-1].upper()


def command_record_implementation_review(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        if state.get("active_stage") != "implementation-review":
            raise HumanizeError("no implementation-review stage is active")
        verify_read_only_guard(repo, state)
        result = resolve_input_file(repo, args.result, "implementation review")
        text = read_text(result, "implementation review")
        require_sections(text, IMPLEMENTATION_REVIEW_SECTIONS, "implementation review")
        verdict = extract_field(text, "Verdict", IMPL_VERDICTS)
        progress = extract_field(text, "Mainline Progress", PROGRESS_VERDICTS)
        if final_marker(text) != verdict:
            raise HumanizeError(f"implementation review must end with the exact marker {verdict}")
        if verdict == "COMPLETE" and progress != "COMPLETE":
            raise HumanizeError("COMPLETE verdict requires Mainline Progress: COMPLETE")
        if verdict != "COMPLETE" and progress == "COMPLETE":
            raise HumanizeError("Mainline Progress: COMPLETE requires Verdict: COMPLETE")

        round_number = int(state["current_round"])
        impl_path = run_dir / f"round-{round_number}-implementation-review.md"
        atomic_copy_text(result, impl_path)
        state["active_stage"] = ""
        state["guard_head"] = ""
        state["guard_status_sha256"] = ""
        state["last_mainline_verdict"] = progress.lower()

        if progress in {"STALLED", "REGRESSED"} or not state.get("last_worker_changed"):
            state["mainline_stall_count"] = int(state.get("mainline_stall_count", 0)) + 1
        else:
            state["mainline_stall_count"] = 0

        if verdict == "BLOCKED":
            terminal = terminalize(run_dir, active, state, "blocked", "implementation reviewer returned BLOCKED")
            output_json(manifest(run_dir, state, terminal))
            return
        if int(state["mainline_stall_count"]) >= 3:
            terminal = terminalize(
                run_dir,
                active,
                state,
                "blocked",
                "three consecutive implementation rounds stalled, regressed, or produced no commit",
            )
            output_json(manifest(run_dir, state, terminal))
            return
        if verdict == "COMPLETE":
            state["phase"] = "code-review"
            state["review_started"] = True
            write_state(active, state)
            append_event(run_dir, "implementation_complete", state, review=str(impl_path))
            output_json(manifest(run_dir, state, active))
            return

        next_round = round_number + 1
        if next_round >= int(state["max_rounds"]):
            terminal = terminalize(
                run_dir,
                active,
                state,
                "failed",
                f"maximum implementation rounds reached ({state['max_rounds']})",
            )
            output_json(manifest(run_dir, state, terminal))
            return
        state["current_round"] = next_round
        state["phase"] = "implementation"
        state["worker_mode"] = "implementation"
        write_state(active, state)
        append_event(run_dir, "implementation_continue", state, review=str(impl_path))
        output_json(manifest(run_dir, state, active))


def command_record_code_review(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        if state.get("active_stage") != "code-review":
            raise HumanizeError("no code-review stage is active")
        verify_read_only_guard(repo, state)
        result = resolve_input_file(repo, args.result, "code review")
        text = read_text(result, "code review")
        require_sections(text, CODE_REVIEW_SECTIONS, "code review")
        verdict = extract_field(text, "Verdict", CODE_VERDICTS)
        if final_marker(text) != verdict:
            raise HumanizeError(f"code review must end with the exact marker {verdict}")
        review_base_match = re.search(r"(?mi)^Review Base:\s*([0-9a-f]{7,40})\s*$", text)
        head_match = re.search(r"(?mi)^Head Commit:\s*([0-9a-f]{7,40})\s*$", text)
        if not review_base_match or not head_match:
            raise HumanizeError("code review must include Review Base and Head Commit fields")
        expected_base = str(state["base_commit"])
        expected_head = head_commit(repo)
        if not expected_base.startswith(review_base_match.group(1)) and not review_base_match.group(1).startswith(expected_base):
            raise HumanizeError("code review used a different base commit")
        if not expected_head.startswith(head_match.group(1)) and not head_match.group(1).startswith(expected_head):
            raise HumanizeError("code review used a different head commit")
        findings = re.findall(r"\[P[0-9]\]", text)
        if verdict == "PASS" and findings:
            raise HumanizeError("PASS code review contains blocking priority findings")
        if verdict == "CHANGES_REQUESTED" and not findings:
            raise HumanizeError("CHANGES_REQUESTED must identify at least one [P0-9] finding")

        round_number = int(state["current_round"])
        code_path = run_dir / f"round-{round_number}-code-review.md"
        atomic_copy_text(result, code_path)
        state["active_stage"] = ""
        state["guard_head"] = ""
        state["guard_status_sha256"] = ""

        if verdict == "BLOCKED":
            terminal = terminalize(run_dir, active, state, "blocked", "code reviewer returned BLOCKED")
            output_json(manifest(run_dir, state, terminal))
            return
        if verdict == "CHANGES_REQUESTED":
            state["current_round"] = round_number + 1
            state["phase"] = "code-fix"
            state["worker_mode"] = "code-fix"
            write_state(active, state)
            append_event(run_dir, "code_changes_requested", state, findings=len(findings), review=str(code_path))
            output_json(manifest(run_dir, state, active))
            return

        state["phase"] = "finalize"
        write_state(active, state)
        finalize_state = run_dir / "finalize-state.md"
        os.replace(active, finalize_state)
        append_event(run_dir, "code_review_passed", state, review=str(code_path))
        output_json(manifest(run_dir, state, finalize_state))


def command_update_goal_tracker(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        source = resolve_input_file(repo, args.input, "goal tracker update")
        text = read_text(source, "goal tracker update")
        require_sections(
            text,
            (
                "## IMMUTABLE SECTION",
                "## MUTABLE SECTION",
                "#### Active Tasks",
                "### Blocking Side Issues",
                "### Queued Side Issues",
                "### Completed and Verified",
                "### Explicitly Deferred",
            ),
            "goal tracker update",
        )
        if sha256_text(goal_immutable_text(text)) != state.get("goal_immutable_sha256"):
            raise HumanizeError("goal tracker update changed the immutable section")
        atomic_copy_text(source, run_dir / "goal-tracker.md")
        write_state(active, state)
        append_event(run_dir, "goal_tracker_updated", state)
        output_json(manifest(run_dir, state, active))


def command_record_finalize(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        repo = validate_active(run_dir, state)
        if active.name != "finalize-state.md" or state.get("phase") != "finalize":
            raise HumanizeError("run is not in finalize phase")
        if state.get("active_stage") != "finalize":
            raise HumanizeError("no finalize stage is active")
        require_clean(repo)
        start_head = str(state.get("worker_start_head", ""))
        current = head_commit(repo)
        if start_head and not is_ancestor(repo, start_head, current):
            raise HumanizeError("finalize worker rewrote or abandoned checkpoint history")
        result = resolve_input_file(repo, args.result, "finalize result")
        text = read_text(result, "finalize result")
        require_sections(text, FINALIZE_SECTIONS, "finalize result")
        atomic_copy_text(result, run_dir / "finalize-summary.md")
        state["head_commit"] = current
        state["active_stage"] = ""
        state["worker_start_head"] = ""
        terminal = terminalize(
            run_dir,
            active,
            state,
            "complete",
            "independent fixed-base code review passed and finalize checks completed",
        )
        output_json(manifest(run_dir, state, terminal))


def command_terminal(args: argparse.Namespace) -> None:
    run_dir, active, _ = load_run(args.run_dir)
    with run_lock(run_dir):
        state = parse_state(active)
        validate_active(run_dir, state)
        target = terminalize(run_dir, active, state, args.status, args.reason)
        output_json(manifest(run_dir, state, target))
