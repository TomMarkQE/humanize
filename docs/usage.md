# Codex Humanizer Usage

## Planning

```text
Use $codex-humanizer-gen-plan with --input draft.md --output docs/goal-plan.md.
```

The root analyzes the Draft, optionally delegates broad repository evidence collection, builds a candidate plan, and sends it to a fresh plan-review child. It writes the final plan only after required evidence and review changes are integrated.

The output schema is pure Codex and contains no `Claude-Codex Deliberation` section.

## Refinement

```text
Use $codex-humanizer-refine-plan with --input docs/goal-plan.md.
```

Supported comment forms are `CMT:` / `ENDCMT`, `<cmt>` / `</cmt>`, and `<comment>` / `</comment>`. Repository-backed `research_request` comments may be delegated; questions and direct changes remain with the root. The default QA directory is `.codex-humanizer/plan_qa`.

## RLCR

```text
Use $codex-humanizer-rlcr to execute docs/goal-plan.md with --base-ref main.
```

The native loop is:

1. root selects one bounded mainline objective;
2. optional research resolves one independent read-heavy question;
3. a sequential worker implements, validates, commits, and summarizes;
4. a fresh implementation reviewer verifies plan and AC progress;
5. when implementation is complete, a fresh code reviewer checks the fixed-base diff;
6. blocking findings return to the worker;
7. fixed-base review pass enters finalization;
8. deterministic finalization creates `complete-state.md`.

### Supported RLCR Arguments

```text
--plan <path>
--max-rounds <N>
--max <N>              compatibility alias
--base-ref <ref>
--track-plan-file
--review-only
--skip-impl            compatibility alias
```

A round is one bounded implementation objective. `--max-rounds` does not count code-review fix cycles as permission to skip a required clean review.

Legacy model, effort, timeout, push, team, quiz, privacy, Claude-answer, and BitLesson flags are not supported. Child model and effort are invocation-time `spawn_agent` fields.

## Terminal States

Artifacts live under `.codex-humanizer/rlcr/<timestamp>/`.

- `complete-state.md`: fixed-base review passed and finalization completed.
- `blocked-state.md`: a user decision, capability, permission, or material replanning need prevents safe progress.
- `failed-state.md`: deterministic failure or maximum bounded implementation rounds.
- `cancelled-state.md`: explicit user cancellation.

Legacy `STOP`, `MAXITER`, or a child claiming “complete” are not terminal evidence.

## Active Plan Changes

The plan snapshot and Goal Tracker immutable section are protected. The root may update only the Goal Tracker mutable section. A material plan, scope, or AC change requires terminating blocked, refining or regenerating the plan, and starting a new RLCR run.
