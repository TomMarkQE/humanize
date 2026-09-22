---
name: humanize
description: Goal-driven implementation planning and iterative review for Codex using native, runtime-selected subagents.
user-invocable: false
disable-model-invocation: true
---

# Humanize for Codex

Humanize keeps requirements and final decisions in the root Codex thread. Native children perform bounded implementation, investigation, and independent review.

The installer hydrates this runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Native workflows

- `$humanize-gen-plan`: preserve the user's Goal and acceptance conditions, investigate repository facts, then obtain independent technical criticism of the candidate plan before activation.
- `$humanize-refine-plan`: refine annotated plans using bounded repository-backed investigation.
- `$humanize-rlcr`: general software implementation/review through the native deterministic RLCR runtime.
- Task-owned App campaigns: read [references/campaign-coordinator.md](references/campaign-coordinator.md) and [references/strategy-review.md](references/strategy-review.md). Protocol `campaign_strategy_v1` restores Goal -> Plan -> implementation -> independent strategy review -> feedback disposition while using the task's existing state and evaluator. Do not start a parallel RLCR runtime.

## Runtime model selection

Use actual native spawn fields: `task_name=cNNN_role_purpose`, V2 `fork_turns: "none"` (V1 `fork_context: false`). An iteration ID is not a child-call count. Reuse the child for coherent same-iteration repairs and its Reviewer for follow-up; a replacement adds `_a02` without renumbering the iteration.

Humanize has no model default. Omit `model` and `reasoning_effort` without an explicit caller/project choice; otherwise pass the requested values as actual fields. Prompt text is not a model override. If a required native capability is unavailable, report the block instead of simulating independence or launching nested model CLIs.

## Global rules

1. Every assignment states the Goal, relevant Plan/AC requirements, current gap, exact local outcome, required prior feedback, immutable base, editable/protected paths, and result location. Links supplement these explicit requirements; they do not replace them.
2. Keep one candidate writer per worktree. Children write only their assigned reports/artifacts; the parent owns decisions and task state.
3. Read-only investigation/criticism must not modify implementation, install dependencies, or run GPU validation. A strategy Reviewer may write only its designated report.
4. Numerical acceptance belongs to the executable evaluator. Strategy review consumes its identity-matched result; it must not become another numerical-validation loop.
5. Complete every mechanism iteration with independent strategy feedback and parent disposition before dependent next-mechanism work. Preparation, parameter trials, and same-mechanism repairs do not each require another child or review.
6. Keep validated incumbent and active exploration separate. Preserve failed reasoning, and revisit rejected directions when their prerequisites change.
7. Do not claim completion from plan/document compliance, a child verdict, or a budget cutoff alone.
