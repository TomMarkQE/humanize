---
name: humanize-gen-plan
description: Generate a structured implementation plan while delegating bounded repository evidence collection to a native read-only Codex subagent.
type: flow
user-invocable: false
disable-model-invocation: true
---

# Humanize Generate Plan for Codex

Transform a draft into the existing Humanize plan schema. Keep requirements, decisions, and final synthesis in the root thread; delegate only independent repository investigation.

The installer hydrates this runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Inputs

- `--input <draft.md>`
- `--output <plan.md>`

Validate first:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-gen-plan-io.sh" --input <draft.md> --output <plan.md>
```

Stop on any non-zero result. Preserve all existing validator exit codes and never overwrite an existing output.

## Delegation boundary

Create one repository-evidence child when any of these are true:

- relevance cannot be established from the draft and already-open files;
- affected code, tests, ownership, dependencies, or current implementation patterns require broad reading;
- feasibility or scope depends on facts distributed across multiple repository areas.

Do not create a child for a tiny or fully specified draft where the root can establish the facts with a few direct reads.

The child owns only this bounded, read-only task:

1. Determine whether the draft maps to this repository.
2. Locate current implementation paths, symbols, tests, validation commands, ownership boundaries, and constraints relevant to the draft.
3. Identify conflicts between the requested outcome and current repository behavior.
4. Return evidence; do not write the final plan or modify the repository.

### Required child result

The child must return exactly these sections:

```markdown
## Relevance
relevant | not_relevant | uncertain

## Evidence
- `path[:line]` — fact and why it matters

## Existing Validation
- command or test path — behavior covered

## Scope and Ownership
- likely changed paths and the reason each is owned

## Risks and Gaps
- contradiction, missing decision, feasibility risk, or uncertainty

## Plan Implications
- concise implications for ACs, boundaries, milestones, and sequencing
```

Reject generic recommendations that are not tied to repository evidence.

## Spawn requirements

Pass a self-contained prompt containing the draft path, repository root, read-only prohibition, and the result schema above.

- V2: use `fork_turns: "none"` and a descriptive `task_name`.
- V1: use `fork_context: false`.
- With no explicit runtime override, omit `model` and `reasoning_effort`.
- With an explicit override, pass both as actual `spawn_agent` fields. Do not put them only in the prompt.

Before spawning, record `HEAD` and `git status --porcelain`. The child may read and run non-mutating discovery commands, but may not edit, commit, install dependencies, or alter generated state.

## Root work while the child runs

Without repeating the repository investigation, the root must continue to:

- extract the goal, non-goals, constraints, quantitative metrics, and unresolved decisions from the draft;
- distinguish hard requirements from trends or preferences;
- prepare the plan skeleton and candidate AC identifiers;
- check the draft for internal clarity, consistency, completeness, and functional contradictions.

Do not immediately wait after spawning unless no useful root work remains.

## Join and integration point

Collect the child before any of these actions:

- final relevance decision;
- final affected-path and ownership decision;
- feasibility hints;
- final AC, milestone, or task synthesis;
- writing the output file.

After collection, verify `HEAD` and worktree state match the pre-spawn snapshot. If the child changed repository state, do not integrate the result; restore or report the violation first.

If the child fails, the root may take over the same bounded investigation, but must state that delegation failed and must not silently omit the missing evidence.

## Output schema

Preserve the existing Humanize plan structure:

```markdown
# Plan Title

## Goal Description

## Acceptance Criteria
- AC-1: ...
  - Positive Tests (expected to PASS):
  - Negative Tests (expected to FAIL):

## Path Boundaries
### Upper Bound (Maximum Scope)
### Lower Bound (Minimum Scope)
### Allowed Choices

## Feasibility Hints and Suggestions

## Dependencies and Sequence

## Task Breakdown

## Claude-Codex Deliberation

## Pending User Decisions

## Implementation Notes
```

Keep identifiers stable, map tests to ACs, and do not place plan terminology into production-code instructions. Write the plan only after all required evidence and user decisions have been integrated. Review the complete output for inconsistent paths, identifiers, routing tags, and language before reporting success.
