---
name: codex-humanizer-rlcr
description: Execute a Goal Plan through a native Codex coordinator, sequential worker, bounded researchers, independent implementation review, and fixed-base code review.
---

# Codex Humanizer Native RLCR Coordinator

The live Codex root thread is the coordinator. It must not implement the plan itself. Writing work belongs to a sequential worker child; bounded repository research and both review layers belong to separate read-only children.

The installer hydrates this deterministic runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

The runtime never invokes a model. It validates Git and plan invariants, serializes state transitions, and writes RLCR artifacts atomically under `.codex-humanizer/rlcr/`.

## Invocation

Normal mode:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" start \
  --plan <plan.md> \
  [--max-rounds <N>] \
  [--base-ref <ref>] \
  [--track-plan-file]
```

Review-only mode:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" start \
  [--plan <plan.md>] \
  --review-only \
  [--base-ref <ref>]
```

`--max` aliases `--max-rounds`; `--skip-impl` aliases `--review-only`. A round is one bounded mainline implementation objective, not an assertion that the entire plan is already finished.

Do not accept legacy model, effort, timeout, team, quiz, push, privacy, or Claude-answer flags. Model, reasoning, sandbox, approval, and wait behavior belong to the live Codex invocation.

Save the returned `run_dir`. Every later state command requires it.

## Native child selection

The caller may choose overrides globally or per role: worker, researcher, implementation reviewer, or code reviewer. Do not save those choices in Skill files, state, repository config, or artifacts.

For every `spawn_agent` call:

- no explicit override: omit `model` and `reasoning_effort`;
- explicit override: include both as actual `spawn_agent` fields;
- V2: use `fork_turns: "none"` or a deliberately bounded positive count and a unique lowercase `task_name`;
- V1: use `fork_context: false`;
- never combine an override with a full-history fork;
- if the active schema cannot express a requested override, terminate blocked with an `agent_unavailable` reason instead of faking the choice or launching another model CLI.

Use self-contained prompts rather than permanent custom agent definitions. Only the root delegates; children must not spawn descendants.

## Ownership and interaction

### Root coordinator

Owns plan and branch validation, user interaction, one mainline objective per round, child prompts, invocation-time model selection, evidence integration, Goal Tracker mutable updates, state transitions, and final reporting.

The root may inspect files and run deterministic checks, but it must not edit implementation files. If a material plan, scope, or acceptance-criteria change becomes necessary, terminate blocked, refine or regenerate the plan, and start a new run.

### Worker child

Owns one bounded implementation or fix objective in the shared worktree. It may edit implementation files, run required validation, commit all changes, and return a structured checkpoint. It must not edit `.codex-humanizer/rlcr/`, the plan snapshot, state, reviewer evidence, or Goal Tracker.

Reuse the same worker with `followup_task` when a fix depends strongly on its implementation context. Never run two writers concurrently.

### Research child

Owns one bounded read-heavy repository or retained-evidence question. It may run non-mutating discovery and analyze existing outputs. It may not edit, commit, install dependencies, run a state-changing benchmark, or decide the final direction.

### Implementation reviewer

A fresh read-only child independently checks the plan, ACs, round contract, worker checkpoint, diff, validation evidence, and Goal Tracker. It verifies evidence rather than trusting the worker summary.

### Code reviewer

A fresh read-only child reviews the exact fixed `base_commit..HEAD` diff for correctness, regressions, security, maintainability, and missing tests. Every blocking finding uses `[P0]` through `[P9]`.

### User decisions

The root first resolves facts from the plan, repository, and current evidence. Ask the user only when the decision is external, policy-bearing, destructive, permission-expanding, irreversible, or not safely derivable. A required unresolved user decision terminates the automatic run as `blocked`; it does not become an invented assumption.

## State-driven procedure

### 1. Re-anchor

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" status --run-dir <run_dir>
```

Read the returned plan, Goal Tracker, phase, round, fixed base, current head, prior review evidence, and current run ledgers. Keep one mainline objective. Queue non-blocking ideas instead of widening it.

### 2. Optional bounded research

Use research only when one independent read-heavy question can be answered and integrated before the writer begins.

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage \
  --run-dir <run_dir> \
  --stage research
```

Require:

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

While it runs, the root must independently prepare the AC mapping, candidate objective, blocking-versus-queued split, and reviewer evidence checklist. Do not immediately join or repeat the investigation.

After collection, save the response to a temporary UTF-8 file and run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-research \
  --run-dir <run_dir> \
  --result <temp-result.md>
```

The runtime rejects a result when branch, `HEAD`, or non-Humanizer worktree state changed during the read-only stage.

### 3. Prepare one worker contract

Create a temporary contract containing exactly these labels:

```markdown
# Round N Contract

Mainline Objective: one bounded result that advances the plan
Target ACs: AC or active review-finding identifiers
Blocking Side Issues In Scope: only issues that prevent this objective
Queued Side Issues Out of Scope: relevant but non-blocking work
Success Criteria: observable code, validation, commit, and evidence conditions
```

Incorporate required research evidence. Do not ask a worker to “finish the whole plan” without a bounded contract.

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage \
  --run-dir <run_dir> \
  --stage worker \
  --contract <contract.md>
```

For `code-fix`, the active code-review findings are the contract and `--contract` is optional.

The worker prompt includes exact plan, Goal Tracker, contract, relevant research/review files, ownership boundaries, validation commands, commit requirements, and the prohibition on editing runtime state.

Require:

```markdown
# Round N Summary

## What Was Implemented

## Files Changed

## Validation
- exact command — result

## Remaining Items
```

While the worker runs, the root must continue non-overlapping no-write work: map contract claims to ACs, prepare the independent review checklist, and identify exact diff/test evidence. Do not inspect an unfinished worker diff and finalize early.

Record the completed checkpoint:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-worker \
  --run-dir <run_dir> \
  --result <temp-summary.md>
```

The runtime requires a clean worktree, descendant history, and the required summary sections.

### 4. Independent implementation review

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage \
  --run-dir <run_dir> \
  --stage implementation-review
```

Spawn a fresh child and require:

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

The final non-empty line must equal `Verdict`. `COMPLETE` is valid only when every in-scope AC has verified evidence and no required work remains. Three consecutive stalled, regressed, or no-commit implementation rounds terminate `blocked` for replanning.

The root may update only the Goal Tracker mutable section through:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" update-goal-tracker \
  --run-dir <run_dir> \
  --input <complete-temp-goal-tracker.md>
```

Then record the review:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-implementation-review \
  --run-dir <run_dir> \
  --result <temp-review.md>
```

`CONTINUE` starts the next bounded worker round. `COMPLETE` enters code review. `BLOCKED` terminates blocked.

### 5. Independent fixed-base code review

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage \
  --run-dir <run_dir> \
  --stage code-review
```

Require the fresh reviewer to inspect the exact returned fixed base and head:

```markdown
# Code Review — Round N

Verdict: PASS | CHANGES_REQUESTED | BLOCKED
Review Base: <exact fixed base commit>
Head Commit: <exact reviewed head commit>

## Findings
- [P0-P9] `path:line` — defect, impact, evidence, and acceptance condition

## Validation Gaps

## Non-blocking Notes

PASS | CHANGES_REQUESTED | BLOCKED
```

`CHANGES_REQUESTED` requires at least one priority finding. `PASS` is invalid when a priority finding remains.

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-code-review \
  --run-dir <run_dir> \
  --result <temp-code-review.md>
```

Changes start a sequential `code-fix` worker round and a fresh reviewer. `PASS` enters finalize. `BLOCKED` terminates blocked.

### 6. Finalize

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" prepare-stage \
  --run-dir <run_dir> \
  --stage finalize
```

Use the existing worker with `followup_task` when available. Limit finalization to simplification, current validation, artifact cleanup, and reporting. Require:

```markdown
# Finalize Summary

## Simplifications

## Validation

## Remaining Risks
```

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-finalize \
  --run-dir <run_dir> \
  --result <temp-finalize.md>
```

The run is complete only when this command creates `complete-state.md`.

## Terminal meanings

- `complete`: implementation evidence is accepted, fixed-base code review passed, and finalization checks completed.
- `blocked`: a required user decision, external capability, permission, native-child capability, or material replanning need prevents safe automatic progress.
- `failed`: deterministic runtime failure or maximum bounded implementation rounds reached.
- `cancelled`: the user explicitly ended the run.

Use:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" terminal \
  --run-dir <run_dir> \
  --status blocked|failed|cancelled \
  --reason <reason>
```

Never claim completion from worker prose, a reviewer statement alone, a clean tree, legacy `STOP`/`MAXITER` markers, or any nested model process.
