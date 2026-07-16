---
name: humanize
description: Goal-driven implementation planning and iterative review for Codex using native, runtime-selected subagents.
user-invocable: false
disable-model-invocation: true
---

# Humanize for Codex

Humanize keeps requirements, decisions, and final synthesis in the root Codex thread while delegating bounded work to native child threads.

The installer hydrates the runtime root below:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Native workflows

- `$humanize-gen-plan`: generate a plan while a bounded read-only child investigates repository evidence.
- `$humanize-refine-plan`: refine annotated plans while repository-backed `research_request` comments are handled by bounded read-only children.
- `$humanize-rlcr`: run a native coordinator loop with a writing worker, optional read-only research, an independent implementation reviewer, and an independent final code reviewer.

The root thread owns orchestration and integration. Shell and Python helpers perform only deterministic validation, Git checks, state transitions, and atomic file writes. They never select or invoke a model.

## Runtime model selection

A caller may choose a child model and reasoning effort for the current invocation. Humanize does not store defaults or routing policy.

For every child:

- When there is no explicit override, omit both `model` and `reasoning_effort` so Codex inherits the current runtime selection.
- When an override is explicitly selected, pass both values as actual `spawn_agent` fields. Text inside the child prompt is not an override.
- Use a non-full-history spawn. With the V2 schema use `fork_turns: "none"`; with the V1 schema use `fork_context: false`.
- If the active `spawn_agent` schema does not expose requested override fields, stop with a capability error rather than pretending the prompt changed the model.

## Global rules

1. Delegate only tasks with a clear ownership boundary and a structured return contract.
2. Keep writing work sequential in the shared worktree.
3. Read-only children must not edit files, commit, or run state-changing commands. Verify the repository did not change before integrating their result.
4. The root thread must continue useful, non-overlapping work before joining a child.
5. Do not finalize before required child evidence is collected and integrated.
6. Do not launch a nested Codex CLI process as a substitute for native child threads.
