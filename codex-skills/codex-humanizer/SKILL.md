---
name: codex-humanizer
description: Codex-native goal planning, plan refinement, implementation, and independent review using runtime-selected native subagents and a deterministic local state machine.
---

# Codex Humanizer

Codex Humanizer keeps requirements, decisions, and final synthesis in the live Codex root thread while delegating bounded work to native child threads.

The installer hydrates the shared runtime root below:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Installed workflows

- `$codex-humanizer-gen-plan`: generate a pure-Codex Goal Plan, using bounded repository research and a fresh independent plan review.
- `$codex-humanizer-refine-plan`: refine annotated plans and delegate only repository-backed `research_request` comments.
- `$codex-humanizer-rlcr`: coordinate a sequential writing worker, optional bounded researchers, a fresh implementation reviewer, and a fresh fixed-base code reviewer.

## Native child contract

For every child:

- With no explicit invocation-time override, omit `model` and `reasoning_effort` so Codex inherits the current root selection.
- With an explicit override, pass both values as actual `spawn_agent` fields. Values mentioned only inside the child message are not overrides.
- Use a non-full-history fork. With V2 use `fork_turns: "none"` or a deliberately bounded positive count; with V1 use `fork_context: false`.
- If the active tool schema cannot express the requested override, stop with an observable capability blocker. Do not silently substitute a model or launch a nested model CLI.
- Give every child a self-contained prompt with exact paths, task ownership, prohibited behavior, and a structured result schema.

The Skills do not persist child model policy, reasoning effort, routing registries, or role-specific model defaults.

## Global ownership

1. The root coordinator owns orchestration, decisions, user interaction, evidence integration, Goal Tracker updates, and terminal reporting.
2. A worker child owns one bounded implementation or fix objective and is the only child authorized to edit implementation files.
3. A research child owns one bounded read-heavy question and returns evidence only.
4. Implementation and code reviewers are fresh read-only children and must verify repository evidence independently.
5. Writing work is sequential in a shared worktree. Never overlap a worker with a researcher or reviewer whose no-write result depends on a stable repository snapshot.
6. The root must continue useful non-overlapping work while a child runs and must collect and integrate required evidence before a dependent write, state transition, or final conclusion.
7. Material changes to an active plan require blocking the current RLCR run, refining or regenerating the plan, and starting a new run. Do not silently rewrite an active plan.

## Deterministic runtime

The Python runtime performs only deterministic work:

- path, plan, branch, base-commit, and worktree validation;
- stage preparation and read-only repository fingerprints;
- worker checkpoint, result-schema, and commit-history validation;
- independent review verdict parsing;
- immutable Goal Tracker protection;
- atomic state and artifact persistence under `.codex-humanizer/`.

It never selects a model, invokes a model, or creates a child. Native `spawn_agent`, follow-up, wait, and collection calls remain the responsibility of the live root thread.

## Unsupported legacy behavior

Do not use Humanize Stop hooks, `codex exec`, `codex review`, Claude/Kimi commands, BitLesson model routing, or legacy RLCR model/timeout flags as substitutes for native child threads.
