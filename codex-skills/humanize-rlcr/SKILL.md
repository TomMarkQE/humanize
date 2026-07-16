---
name: humanize-rlcr
description: Execute Humanize RLCR as a native Codex coordinator with runtime-selected worker, research, implementation-review, and code-review subagents.
type: flow
user-invocable: false
disable-model-invocation: true
---

# Humanize Native RLCR Coordinator

The current Codex root thread is the coordinator. It must not implement the plan itself. Writing work belongs to a worker child; repository research and both review layers belong to separate read-only children.

The installer hydrates this deterministic runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

The runtime never invokes a model. It validates Git and plan invariants, serializes state transitions, and writes RLCR artifacts atomically.

## Invocation

Normal mode:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" start --plan <plan.md> [--max <N>] [--base-ref <ref>] [--track-plan-file]
```

Review-only mode:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" start [--plan <plan.md>] --review-only [--base-ref <ref>]
```

`--skip-impl` is accepted as a compatibility alias for `--review-only` by the runtime. Model, reasoning, sandbox, and approval choices are runtime Codex choices and are not CLI options or persisted state.

Save the returned `run_dir`. Every later state command requires it.

## Native child rules

The root may receive invocation-time overrides globally or per role: worker, researcher, implementation reviewer, code reviewer. Do not save them in files.

For every `spawn_agent` call:

- No explicit override: omit `model` and `reasoning_effort` so normal inheritance applies.
- Explicit override: include both as actual `spawn_agent` fields on the call. Merely naming them inside `message` does not count.
- V2: use `fork_turns: "none"` and a unique lowercase `task_name`.
- V1: use `fork_context: false`.
- Never combine an override with a full-history fork.
- If requested fields are unavailable in the active tool schema, record `agent_unavailable` and stop blocked. Do not fake an override or launch a nested Codex CLI process.

Only the root thread delegates. Children must not spawn grandchildren.

## Ownership

### Root coordinator

Owns:

- plan and branch validation;
- one mainline objective per round;
- child prompt construction and runtime model selection;
- all `.humanize/rlcr/<run>/` writes through the deterministic runtime;
- evidence integration, goal-tracker mutable updates, and state transitions;
- deciding when a child result is sufficient to continue.

The root may inspect files and run deterministic checks, but it must not edit implementation files.

### Worker child

Owns sequential writing work in the shared worktree:

- implement or repair the current bounded objective;
- run appropriate validation;
- commit all implementation changes;
- return a structured checkpoint.

The worker must not edit RLCR state, plan snapshots, review files, or the goal tracker. Reuse the same worker with `followup_task` when the next round depends strongly on its implementation context. Spawn a replacement only when the prior worker is unavailable or a clean context is materially safer.

### Research child

Owns one bounded read-only repository or evidence investigation. It may run non-mutating discovery and profiling-result analysis, but may not edit, commit, install dependencies, or run a state-changing benchmark. Use it only when the result can be collected before the writer begins.

### Implementation reviewer

A fresh read-only child independently checks the plan, ACs, round contract, worker checkpoint, diff, tests, and goal tracker. It must not trust the worker summary without verifying repository evidence.

### Code reviewer

A fresh read-only child independently reviews the fixed `base_commit..HEAD` diff for correctness, regressions, security, maintainability, and missing tests. It uses `[P0]` through `[P9]` for every blocking finding. It must not edit or commit.

## Round procedure

### 1. Validate state

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" status --run-dir <run_dir>
```

Read the returned plan, goal tracker, phase, round, fixed base, and current head.

### 2. Optional bounded research

Use research only when a specific unresolved fact blocks a high-quality worker contract.

Before spawning:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage --run-dir <run_dir> --stage research
```

Required child result:

```markdown
## Findings
- observed facts only

## Evidence
- `path[:line]`, symbol, test output, profile artifact, or retained measurement

## Implications
- consequences for the current round objective

## Unknowns
- remaining uncertainty and the cheapest discriminating check
```

While research runs, the root must independently prepare the AC mapping, candidate mainline objective, blocking-versus-queued issue split, and review checklist. Do not immediately join and do not repeat the same investigation.

After collection, write the child response to a temporary UTF-8 file and record it:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-research --run-dir <run_dir> --result <temp-result.md>
```

The runtime verifies that the read-only child did not change `HEAD` or the worktree.

### 3. Prepare one round contract

Create a temporary contract with all labels below:

```markdown
# Round N Contract

Mainline Objective: one bounded result that directly advances the plan
Target ACs: AC identifiers or review finding identifiers
Blocking Side Issues In Scope: only issues that prevent this objective
Queued Side Issues Out of Scope: relevant but non-blocking work
Success Criteria: observable code, test, and evidence conditions
```

A contract must incorporate any required research result. Never ask the worker to “finish the whole plan” without a bounded objective.

### 4. Spawn or continue the worker

Checkpoint the stage:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage --run-dir <run_dir> --stage worker --contract <contract.md>
```

For a `code-fix` phase, use the active code-review findings as the contract; `--contract` is not required.

The worker prompt must include:

- plan, goal tracker, round contract, prior relevant review, and research paths;
- the exact implementation ownership boundary;
- requirement to keep the branch and workload constraints unchanged;
- requirement to run validation, commit all changes, and leave the worktree clean;
- prohibition on modifying `.humanize/rlcr/<run>/`.

Required worker return:

```markdown
# Round N Summary

## What Was Implemented

## Files Changed

## Validation
- exact command — result

## Remaining Items

## BitLesson Delta
Action: add | update | none
Lesson ID(s): ... | NONE
Notes: ...
```

While the worker runs, the root must continue non-overlapping work: prepare the independent review checklist, map contract claims to ACs, and identify the exact diff/test evidence the reviewer must verify. The root must not inspect an unfinished worker diff and finalize early.

After the worker completes, write its response to a temporary file and record it:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-worker --run-dir <run_dir> --result <temp-summary.md>
```

The runtime requires a clean worktree, non-rewritten checkpoint history, and the existing summary sections.

### 5. Independent implementation review

When the phase is `implementation-review`:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage --run-dir <run_dir> --stage implementation-review
```

Spawn a fresh read-only reviewer. Its prompt must require direct inspection of the plan, goal tracker, contract, summary, branch diff, and validation evidence.

Required return:

```markdown
# Implementation Review — Round N

Verdict: CONTINUE | COMPLETE | BLOCKED
Mainline Progress: ADVANCED | STALLED | REGRESSED | COMPLETE

## Verified Evidence

## Acceptance-Criteria Status

## Blocking Issues

## Queued Follow-up

## Required Next Objective

CONTINUE | COMPLETE | BLOCKED
```

The last non-empty line must exactly equal the `Verdict`. `COMPLETE` is allowed only when every in-scope AC has sufficient evidence and no unresolved required work remains.

Record it:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-implementation-review --run-dir <run_dir> --result <temp-review.md>
```

Before recording, the root may update only the goal tracker's mutable section. Use a complete temporary goal tracker and apply it atomically:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" update-goal-tracker --run-dir <run_dir> --input <temp-goal-tracker.md>
```

Do not alter the immutable goal or AC section.

A `CONTINUE` verdict starts the next bounded worker round. A `BLOCKED` verdict terminates blocked. `COMPLETE` enters independent code review.

### 6. Independent fixed-base code review

When the phase is `code-review`:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage --run-dir <run_dir> --stage code-review
```

Spawn a fresh read-only code reviewer. The prompt must explicitly use the returned fixed base and head commits, inspect `base_commit..HEAD`, and ignore unrelated pre-existing code.

Required return:

```markdown
# Code Review — Round N

Verdict: PASS | CHANGES_REQUESTED | BLOCKED
Review Base: <exact fixed base commit>
Head Commit: <exact reviewed head commit>

## Findings
- [P0-P9] `path:line` — blocking defect, impact, and required correction

## Validation Gaps

## Non-blocking Notes

PASS | CHANGES_REQUESTED | BLOCKED
```

`CHANGES_REQUESTED` requires at least one `[P0-9]` finding. `PASS` is invalid when such a finding is present. The final marker must match the verdict.

Record it:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-code-review --run-dir <run_dir> --result <temp-code-review.md>
```

Findings start a sequential `code-fix` worker round, followed by a fresh code reviewer. A `BLOCKED` verdict terminates blocked. `PASS` enters finalize.

### 7. Finalize

When the phase is `finalize`, checkpoint a final worker task:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage --run-dir <run_dir> --stage finalize
```

Use the existing worker via `followup_task` when available. Limit finalization to simplification, current validation, cleanup of accidental artifacts, and final reporting; do not widen scope.

Required return:

```markdown
# Finalize Summary

## Simplifications

## Validation

## Remaining Risks
```

Record completion:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-finalize --run-dir <run_dir> --result <temp-finalize.md>
```

The run is complete only after this command creates `complete-state.md`.

## Failure handling

- Required native child unavailable or requested override fields unavailable: terminate `blocked` with `agent_unavailable` in the reason.
- Permission prevents required worker work: terminate `blocked` with `permission_denied`.
- Malformed child result, branch change, plan tampering, dirty worker checkpoint, rewritten history, or invalid review base: fix the condition and retry; do not manually edit state.
- Maximum implementation rounds reached: runtime terminates `failed`.
- User cancellation:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" terminal --run-dir <run_dir> --status cancelled --reason <reason>
```

Never claim completion from child prose alone. The root must integrate every required result and reach deterministic `complete-state.md`.
