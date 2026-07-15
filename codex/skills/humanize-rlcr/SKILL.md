---
name: humanize-rlcr
description: Run Humanize's Codex-native implementation and independent review loop with visible worker and reviewer subagent threads.
---

# Humanize RLCR for Codex

Use this skill when the user asks Humanize to implement a plan, continue an existing Humanize run, or review the current branch until blocking findings are resolved.

This is the Codex-native workflow. The current Codex thread is the coordinator. Every model-backed implementation, investigation, and review step must be delegated through Codex's native subagent system so the resulting child thread is visible and openable in Codex App, CLI, and IDE.

## Non-negotiable execution boundary

- Never run `codex exec`, `codex review`, another `codex` process, or any other model CLI from a shell command.
- Never rely on a Stop hook to start model work.
- Never describe a shell script, background process, log tail, or state file as an agent.
- Scripts may only perform deterministic validation, Git inspection, state persistence, and review-contract parsing.
- Do not silently fall back to implementation or review in the coordinator when a required native agent cannot be spawned. Persist a blocked state and explain the failure.
- The coordinator is the only thread that may delegate. Child agents must not spawn descendants. This keeps the workflow compatible with the default `agents.max_depth = 1`.

The installer replaces `{{HUMANIZE_RUNTIME_ROOT}}` with the absolute installed runtime path.

## Supported arguments

Interpret the user's arguments as follows:

- First positional path: implementation plan inside the current repository.
- `--max N` or `--max-rounds N`: maximum total rounds. Default: 42.
- `--base-ref REF` or `--base-branch REF`: comparison base. Default: local `main`, then `master`, then the starting branch commit.
- `--track-plan-file`: fail if the source plan changes during the run.
- `--review-only` or legacy alias `--skip-impl`: skip plan implementation and start with independent code review. A plan is optional.

Do not accept these legacy Codex options: `--codex-model`, `--codex-timeout`, `--agent-teams`, `--claude-answer-codex`, or `--yolo`. Explain that model, effort, sandbox, and approval behavior now come from the current Codex session and installed custom-agent configuration.

## Native agents

Use the installed custom agents by their exact names:

- `humanize_worker`: writes implementation and fix commits.
- `humanize_implementation_reviewer`: independently checks plan alignment and completion.
- `humanize_code_reviewer`: independently checks the branch diff for blocking defects.
- `humanize_researcher`: performs read-only analysis requested by `analyze` tasks or by the coordinator.

Writing agents run one at a time. Read-only research may run concurrently only when the questions are independent. Never run a reviewer in the same child thread that produced the implementation being reviewed.

## Start or resume

First inspect `.humanize/rlcr/*/state.json` for a state whose `engine` is `codex-native` and whose status is `active`. If one exists, run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" status --loop-dir <loop-dir>
```

Resume from the returned `next_action`. Do not create a second active loop.

For a new implementation run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" init \
  --project-root . \
  --plan-file <plan-path> \
  --max-rounds <N> \
  [--base-ref <ref>] \
  [--track-plan-file]
```

For review-only mode:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" init \
  --project-root . \
  --review-only \
  --max-rounds <N> \
  [--base-ref <ref>]
```

Read the JSON response. Treat `loop_dir`, `state_file`, `plan_snapshot`, `goal_tracker`, `summary_file`, `base_commit`, `phase`, `round`, and `next_action` as authoritative. Initialization fails when another native loop is active or when non-Humanize project changes already exist. An untracked source plan may remain outside Git; the immutable loop snapshot is still authoritative.

## Coordinator loop

Repeat the following state-driven cycle until the runtime returns a terminal action.

### 1. Re-anchor

Before every delegation, read:

- `<loop-dir>/state.json`
- `<loop-dir>/plan.md`
- `<loop-dir>/goal-tracker.md`
- the current `round-<N>-summary.md`
- all review files from the immediately preceding round
- the relevant Git history and diff from `base_commit`

Keep one mainline objective for the current round. Record non-blocking ideas under queued follow-up instead of widening the mainline.

Run the deterministic invariant check before spawning new work:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" validate --loop-dir <loop-dir>
```

A non-zero result is a real failure. Do not continue around it.

### 2. Research, when needed

The root coordinator owns research delegation because child agents may not create descendants.

Spawn `humanize_researcher` when either condition holds:

- the plan marks a task as `analyze`; or
- a worker/reviewer result identifies a concrete question that must be resolved before safe implementation.

Give the researcher one bounded question, relevant paths, the plan snapshot, and the required evidence format. Wait for the result. Save useful findings under `<loop-dir>/research-<round>-<slug>.md`, then include those paths and conclusions in the worker prompt.

A cancelled, unavailable, or permission-blocked researcher is not automatically fatal if the question is optional. It is fatal when the unresolved question blocks implementation or review.

### 3. Delegate implementation or fixes

When `next_action` is `delegate_worker`, spawn exactly one `humanize_worker` child thread. Its prompt must include:

- the loop directory and current state path;
- the immutable plan snapshot and current goal tracker;
- the current round and phase;
- the single mainline objective;
- relevant prior reviewer findings and research results;
- the required summary path;
- the requirement to run relevant tests, commit the changes, and leave non-Humanize repository files clean;
- the rule that the child may write only the requested round summary inside the loop directory and may not edit state, plan, goal tracker, locks, research, or reviewer evidence.

Wait for the worker. Inspect its result and repository state rather than trusting the prose summary alone. The worker must write the round summary with at least `Work Completed`, `Files Changed`, `Validation`, and `Remaining Items` sections.

If the worker stopped before producing a usable commit and summary, steer that same child thread once with the missing concrete requirements. If it still cannot finish, persist the failure:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" fail \
  --loop-dir <loop-dir> \
  --code agent_failed \
  --message <concise-explanation>
```

After successful work, run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" checkpoint \
  --loop-dir <loop-dir> \
  --summary-file <loop-dir>/round-<N>-summary.md
```

The checkpoint rejects missing summaries, uncommitted non-Humanize changes, branch drift, rewritten history, plan tampering, and rounds without a new descendant commit. Runtime lock files serialize state transitions; do not bypass them or invoke overlapping state commands deliberately.

### 4. Delegate implementation review

When `next_action` is `delegate_implementation_reviewer`, spawn a fresh `humanize_implementation_reviewer` thread. Give it the plan snapshot, goal tracker, current summary, base commit, current commit, relevant tests, and permission to inspect the repository read-only.

Require its verbatim response to contain exactly one line of each form:

```text
HUMANIZE_IMPLEMENTATION_REVIEW: continue|complete|blocked
MAINLINE_PROGRESS: advanced|stalled|regressed
```

Save the full response to `<loop-dir>/round-<N>-implementation-review.md`, then run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-review \
  --loop-dir <loop-dir> \
  --kind implementation \
  --review-file <loop-dir>/round-<N>-implementation-review.md
```

`continue` creates the next implementation round. `complete` moves to independent code review. `blocked` stops the automatic loop. Three consecutive stalled/regressed implementation verdicts also block the loop for replanning.

### 5. Delegate code review

When `next_action` is `delegate_code_reviewer`, spawn a fresh `humanize_code_reviewer` thread. Give it the immutable plan when available, `base_ref`, `base_commit`, current commit, changed files, test evidence, and prior code-review findings.

Require its verbatim response to contain exactly one line:

```text
HUMANIZE_CODE_REVIEW: changes_required|pass|blocked
```

Every blocking finding under `changes_required` must begin with `[P0]` through `[P9]` and include a path or symbol, impact, evidence, and a concrete acceptance condition. A `pass` response must contain no unresolved `[P0-9]` marker.

Save the full response to `<loop-dir>/round-<N>-code-review.md`, then run:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" record-review \
  --loop-dir <loop-dir> \
  --kind code \
  --review-file <loop-dir>/round-<N>-code-review.md
```

`changes_required` creates a fix round for `humanize_worker`. `pass` completes the loop. `blocked` stops automatic progress.

### 6. Keep the goal tracker current

The coordinator, not a reviewer, owns `<loop-dir>/goal-tracker.md`. After each valid review:

- move verified acceptance criteria into `Verified Outcomes` with commit/test evidence;
- keep unresolved blocking findings visible;
- queue non-blocking cleanup instead of treating it as completion work;
- record any justified plan interpretation without editing `<loop-dir>/plan.md`.

Do not mark an acceptance criterion verified solely because a worker claimed it was complete.

## Failure, cancellation, and permissions

Never hide a failed or cancelled child thread behind a generic retry.

Use the deterministic failure command with the most accurate code:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" fail \
  --loop-dir <loop-dir> \
  --code agent_unavailable|permission_denied|cancelled|interrupted|agent_failed|validation_failed \
  --message <what-happened-and-what-remains>
```

- If native subagents are unavailable, use `agent_unavailable`. Do not launch a nested CLI fallback.
- If inherited sandbox or approval policy prevents required work, use `permission_denied` and identify the blocked operation.
- If the user stops the workflow, use `cancelled`.
- If the task or child thread is interrupted unexpectedly, use `interrupted`.

The current parent session's permission and sandbox policy applies to subagents. Ask for a broader parent permission mode only when the user chooses to continue and the blocked operation is necessary.

## Completion report

A loop is complete only when runtime status is `complete` and `next_action` is `report_complete` after a valid independent code-review `pass` verdict.

Report:

- the user goal and final status;
- implementation and review rounds completed;
- the final commit and comparison base;
- validation commands and results;
- the native child agent roles used, so the user can open their threads;
- the loop directory containing state, summaries, and reviewer results;
- queued non-blocking follow-up and known limitations.

Do not claim completion from a worker result, a clean working tree, or an implementation-review `complete` verdict alone.
