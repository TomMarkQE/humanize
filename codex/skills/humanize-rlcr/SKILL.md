---
name: humanize-rlcr
description: Run Humanize's Codex-native implementation and independent review loop with runtime-selected visible worker, researcher, and reviewer child threads.
---

# Humanize Codex-native workflow: RLCR

Use this skill to implement a Humanize plan, continue an active native run, or review the current branch until blocking findings are resolved. The current Codex root thread is the coordinator. It owns state, delegation, integration, and final reporting; it does not perform the assigned implementation or independent reviews itself.

The installer replaces `{{HUMANIZE_RUNTIME_ROOT}}` with the absolute deterministic runtime path.

## Non-negotiable boundary

- Never run `codex exec`, `codex review`, another `codex` process, or another model CLI from shell.
- Never use a Stop hook to start model work.
- Scripts may only validate repository state, inspect Git, persist state, write deterministic scaffolds, and parse reviewer contracts.
- The root coordinator is the only thread that delegates. Child roles never spawn descendants.
- Effective child sandbox and approval behavior inherit from the live parent task after role selection.
- Use exactly one repository-writing worker at a time. No researcher or reviewer may overlap with a worker or any other repository writer.
- Independent behaviorally no-write research may overlap only with other no-write research when questions and evidence scopes do not overlap.
- A worker must never review its own implementation. Each implementation review and code review uses a fresh reviewer child.
- Researcher and reviewer no-write rules are mandatory role contracts, not claims of a separately enforced sandbox. The coordinator verifies the branch, `HEAD`, index, tracked-file status, and untracked non-Humanize set before integrating their results.
- If a required child cannot be created, persist a blocked or failed state. Do not silently perform the role in the coordinator or launch a nested CLI fallback.

A no-write child that changes HEAD, the index, tracked files, or untracked non-Humanize files has violated its role contract. Do not integrate its result, advance runtime state, or automatically restore/discard the change. Record the exact delta and persist `agent_failed` or `permission_denied` as appropriate.

## Supported workflow arguments

Interpret:

- first positional path: plan inside the current repository;
- `--max N` or `--max-rounds N`: maximum rounds, default 42;
- `--base-ref REF` or `--base-branch REF`: fixed comparison base;
- `--track-plan-file`: fail if the original plan changes;
- `--review-only` or legacy `--skip-impl`: start with independent code review.

Legacy shell-review options such as `--codex-model`, `--codex-timeout`, `--claude-answer-codex`, `--agent-teams`, and `--yolo` are not native RLCR state or config. Invocation-time model and effort choices are expressed in the user's request and applied directly to each `spawn_agent` call.

## Runtime role selection

Humanize stores no model or reasoning-effort defaults. Resolve an invocation-time selection for each role:

- `worker`;
- `researcher`;
- `implementation_reviewer`;
- `code_reviewer`.

A request may choose one override for all children or different overrides per role. Unmentioned roles inherit. Do not persist this role map in Humanize config, the plan, state JSON, or an agent definition.

For every child spawn:

1. Select the exact custom `agent_type` below.
2. Provide a self-contained prompt with paths and evidence because a full-history fork is not compatible with custom role/model overrides.
3. In the inheritance case, omit `model` and `reasoning_effort`.
4. In the explicit override case, pass the requested `model` and `reasoning_effort` as actual fields.
5. V2 uses `fork_turns: "none"` or a deliberately bounded positive turn count. V1 uses `fork_context: false`.
6. Never use `fork_turns: "all"` or `fork_context: true` with `agent_type`, `model`, or `reasoning_effort`.
7. When child activity metadata exposes the effective model/effort, verify an explicit request. Unsupported or mismatched overrides are runtime blockers, not permission to substitute or silently inherit.

Writing a model name inside the child message does not satisfy this contract.

## Installed native roles

- `humanize_worker`: the only role behaviorally authorized to implement and commit fixes; effective permissions inherit from the parent.
- `humanize_researcher`: bounded evidence analysis under a mandatory no-write contract; effective permissions inherit from the parent.
- `humanize_implementation_reviewer`: independent plan/AC/mainline review under a mandatory no-write contract.
- `humanize_code_reviewer`: independent final branch-diff review under a mandatory no-write contract.

## Start or resume

Before creating a run, inspect `.humanize/rlcr/*/state.json` for an active state with `engine: codex-native`. Resume it instead of creating a second loop.

Status:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" status --loop-dir <loop-dir>
```

New implementation run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" init \
  --project-root . \
  --plan-file <plan-path> \
  --max-rounds <N> \
  [--base-ref <ref>] \
  [--track-plan-file]
```

Review-only run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" init \
  --project-root . \
  --review-only \
  --max-rounds <N> \
  [--base-ref <ref>]
```

Treat returned `loop_dir`, `state_file`, `plan_snapshot`, `goal_tracker`, `summary_file`, `base_commit`, `phase`, `round`, and `next_action` as authoritative. Initialization and every state transition fail closed on dirty project changes, branch drift, rewritten history, plan tampering, corrupt state, or concurrent native loops.

## Coordinator cycle

Repeat from runtime `next_action` until it returns a terminal report action.

### Re-anchor and validate

Before delegation, read:

- state JSON;
- immutable plan snapshot;
- current goal tracker;
- current summary scaffold and immediately preceding review files;
- relevant run-owned evidence named by the plan;
- Git history and diff from the fixed base commit.

Choose one mainline objective for the round. Queue non-blocking ideas instead of widening it.

Run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" validate --loop-dir <loop-dir>
```

Do not continue after a non-zero result.

### No-write child baseline

Before every researcher or reviewer spawn, record:

- current branch and exact `HEAD`;
- staged and unstaged tracked-file status;
- untracked non-Humanize files;
- any pre-existing dirty state that must remain byte-for-byte attributable.

Do not start a no-write child while a worker is active. While a no-write child runs, the root may read, reason, normalize objectives, map acceptance conditions, prepare prompts/checklists in memory, and inspect deterministic state, but it must not modify repository state.

Before saving, integrating, or acting on the child result, compare the branch, `HEAD`, index, tracked-file status, and untracked non-Humanize set with the recorded baseline. On mismatch, do not integrate the result or call `record-review`; report the exact delta and persist a failure. On a matching baseline, continue with evidence verification.

### Delegate bounded research when it changes the next action

Spawn `humanize_researcher` only for an `analyze` task or a precise question that must be resolved before a safe edit, measurement, or review. Do not spawn a general-purpose researcher to “look around.”

The prompt must specify:

- the single question and decision it supports;
- plan/task/run paths and authoritative source boundaries;
- current implementation and evidence paths to inspect;
- already rejected directions or established facts that must not be repeated;
- prohibited writes and prohibited generic advice;
- the expected evidence structure.

Require observed facts with paths/symbols/measurements, competing explanations, decision impact, cheapest discriminating step, and uncertainty. Domain repositories may impose a stricter contract, such as kernel mechanism, ranked direction, correctness risk, and falsifiable hypothesis fields; include it verbatim.

While research runs, the coordinator must continue useful non-overlapping no-write work: normalize the round objective, inspect deterministic state, map acceptance conditions, prepare the worker evidence checklist, and identify exactly which decision depends on the result. Do not redo the research, write repository files, or immediately wait when local work remains.

Before spawning a worker or reviewer whose task depends on research, collect the child, verify the no-write baseline, verify load-bearing citations, save the useful result under `<loop-dir>/research-<round>-<slug>.md`, and integrate its conclusion into the next prompt. The result file is written by the coordinator only after the child is closed and baseline verification passes. Optional failed research may be skipped only when the unresolved question no longer affects the next action; record why.

### Delegate implementation or fixes

When `next_action` is `delegate_worker`, spawn exactly one `humanize_worker` child. Its self-contained prompt must include:

- loop directory and state path;
- immutable plan snapshot and goal tracker;
- current phase and round;
- one mainline objective and mapped acceptance criteria;
- relevant research and prior reviewer findings;
- editable and protected paths;
- required correctness/performance/test commands from the plan;
- required summary path;
- requirement to commit all non-Humanize changes and leave the tree clean;
- prohibition on editing state, plan snapshot, goal tracker, locks, research files, or reviewer evidence.

The worker receives the live parent permission profile. If those permissions cannot perform a required operation, the worker reports the exact blocker instead of changing policy or requesting a hidden fallback.

While the worker runs, the coordinator may prepare independent verification inputs, inspect prior evidence, and construct the reviewer checklist in memory. It must not edit the worker's files, run the same implementation, launch a no-write reviewer/researcher whose baseline would overlap writer activity, or claim the worker result before collection.

Collect the worker before checkpointing. Inspect repository state, commit ancestry, summary, and actual test artifacts rather than trusting prose. If the child returns a precise `NEEDS_RESEARCH` question, finish/close the worker, establish a clean no-write baseline, resolve it through the root researcher, then send a follow-up to the same worker only when the runtime can safely resume it. A worker may receive one concrete corrective follow-up for an incomplete result; persistent failure is recorded with the runtime `fail` command.

Checkpoint:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" checkpoint \
  --loop-dir <loop-dir> \
  --summary-file <loop-dir>/round-<N>-summary.md
```

### Delegate implementation review

When `next_action` is `delegate_implementation_reviewer`, establish the no-write baseline, then spawn a fresh `humanize_implementation_reviewer`. Include the immutable plan, goal tracker, fixed base/current commits, worker summary, actual diff, relevant evidence, commands/results, round objective, and previous findings.

Require exactly one of each marker:

```text
HUMANIZE_IMPLEMENTATION_REVIEW: continue|complete|blocked
MAINLINE_PROGRESS: advanced|stalled|regressed
```

The reviewer must independently inspect the repository and treat the worker summary as a claim. While it runs, the coordinator may reconcile deterministic evidence locations and prepare possible state transitions in memory, but must not modify repository state, duplicate the review, or pre-decide completion.

Collect the reviewer, verify the no-write baseline, and verify its cited evidence. Only then may the coordinator save the complete result to `<loop-dir>/round-<N>-implementation-review.md` and record it:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-review \
  --loop-dir <loop-dir> \
  --kind implementation \
  --review-file <loop-dir>/round-<N>-implementation-review.md
```

`continue` opens another worker round; `complete` moves to independent code review; `blocked` stops automatic progress. Repeated stalled/regressed verdicts trigger the runtime's replan/stop semantics.

### Delegate final code review

When `next_action` is `delegate_code_reviewer`, establish the no-write baseline, then spawn a fresh `humanize_code_reviewer`. Include the immutable plan when available, fixed base ref/commit, current commit, full changed-file list and diff, test evidence, protected boundaries, and unresolved prior findings.

Require exactly one marker:

```text
HUMANIZE_CODE_REVIEW: changes_required|pass|blocked
```

Every blocking finding under `changes_required` starts with `[P0]` through `[P9]` and names a path/symbol, impact, evidence or reproduction, and concrete resolution condition. `pass` contains no unresolved priority marker.

Collect the reviewer, verify the no-write baseline, and verify cited evidence. Only then may the coordinator save the full result to `<loop-dir>/round-<N>-code-review.md` and run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-review \
  --loop-dir <loop-dir> \
  --kind code \
  --review-file <loop-dir>/round-<N>-code-review.md
```

`changes_required` returns to the worker; `pass` completes the loop; `blocked` stops automatic progress. Never finalize from worker completion or implementation-review completion alone.

## Goal tracker and integration ownership

The coordinator owns the goal tracker. After a valid review, update it only with verified commit/test evidence, unresolved blockers, queued non-blocking follow-up, and justified interpretations. Never mark an AC verified solely because a child claimed success.

Do not write final state, report completion, or move to the next role until every required child result has been collected, no-write baseline checked when applicable, evidence verified, and the result integrated into the authoritative runtime transition.

## Failure and cancellation

Persist accurate terminal failures:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" fail \
  --loop-dir <loop-dir> \
  --code agent_unavailable|permission_denied|cancelled|interrupted|agent_failed|validation_failed \
  --message <concise explanation>
```

Use `agent_unavailable` for missing native subagent capability or unsupported required override, `permission_denied` for inherited sandbox/approval blockers, `cancelled` when the user stops, and `agent_failed` or `validation_failed` for unusable child/results or no-write role violations. Do not hide a child failure behind a generic retry.

## Completion report

A run is complete only when runtime status is `complete` and `next_action` is `report_complete` after a valid, baseline-verified independent code-review `pass`.

Report the goal and final status, rounds, final and base commits, exact validations and outcomes, native child roles and effective explicit overrides when observable, loop evidence paths, queued follow-up, and known limitations. Never claim that native forwarding was tested when the runtime did not expose or execute a real child spawn.
