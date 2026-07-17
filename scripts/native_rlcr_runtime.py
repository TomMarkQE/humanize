#!/usr/bin/env python3
"""CLI for the deterministic Codex Humanizer RLCR runtime."""

from native_rlcr_review import *  # noqa: F401,F403 - internal sibling runtime surface


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Deterministic state machine for Codex Humanizer native RLCR. It never invokes a model."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    start = subparsers.add_parser("start", help="initialize a native RLCR run")
    start.add_argument("--repo", help="repository path; defaults to current directory")
    start.add_argument("--plan", help="implementation plan path")
    start.add_argument(
        "--max-rounds",
        "--max",
        dest="max_rounds",
        type=int,
        default=42,
        help="maximum bounded implementation rounds (default: 42)",
    )
    start.add_argument("--base-ref", help="fixed review base ref")
    start.add_argument("--track-plan-file", action="store_true")
    start.add_argument("--review-only", action="store_true")
    start.add_argument("--skip-impl", action="store_true", help="compatibility alias for --review-only")
    start.set_defaults(func=command_start)

    status = subparsers.add_parser("status", help="validate and print the active run manifest")
    status.add_argument("--run-dir", required=True)
    status.set_defaults(func=command_status)

    prepare = subparsers.add_parser("prepare-stage", help="validate and checkpoint before a child stage")
    prepare.add_argument("--run-dir", required=True)
    prepare.add_argument(
        "--stage",
        required=True,
        choices=("research", "worker", "implementation-review", "code-review", "finalize"),
    )
    prepare.add_argument("--contract", help="round contract for an implementation worker")
    prepare.set_defaults(func=command_prepare_stage)

    research = subparsers.add_parser("record-research", help="verify and persist read-only research evidence")
    research.add_argument("--run-dir", required=True)
    research.add_argument("--result", required=True)
    research.set_defaults(func=command_record_research)

    worker = subparsers.add_parser("record-worker", help="validate and persist a worker checkpoint")
    worker.add_argument("--run-dir", required=True)
    worker.add_argument("--result", required=True)
    worker.set_defaults(func=command_record_worker)

    impl_review = subparsers.add_parser(
        "record-implementation-review", help="validate and apply an independent implementation review"
    )
    impl_review.add_argument("--run-dir", required=True)
    impl_review.add_argument("--result", required=True)
    impl_review.set_defaults(func=command_record_implementation_review)

    code_review = subparsers.add_parser("record-code-review", help="validate and apply an independent code review")
    code_review.add_argument("--run-dir", required=True)
    code_review.add_argument("--result", required=True)
    code_review.set_defaults(func=command_record_code_review)

    goal = subparsers.add_parser("update-goal-tracker", help="atomically replace the mutable goal tracker content")
    goal.add_argument("--run-dir", required=True)
    goal.add_argument("--input", required=True)
    goal.set_defaults(func=command_update_goal_tracker)

    finalize = subparsers.add_parser("record-finalize", help="validate finalization and complete the run")
    finalize.add_argument("--run-dir", required=True)
    finalize.add_argument("--result", required=True)
    finalize.set_defaults(func=command_record_finalize)

    terminal = subparsers.add_parser("terminal", help="explicitly block, fail, or cancel an active run")
    terminal.add_argument("--run-dir", required=True)
    terminal.add_argument("--status", choices=("blocked", "failed", "cancelled"), required=True)
    terminal.add_argument("--reason", required=True)
    terminal.set_defaults(func=command_terminal)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "skip_impl", False):
        args.review_only = True
    if getattr(args, "max_rounds", 1) < 1:
        parser.error("--max-rounds must be at least 1")
    try:
        args.func(args)
        return 0
    except HumanizeError as exc:
        print(f"codex-humanizer-rlcr: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("codex-humanizer-rlcr: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
