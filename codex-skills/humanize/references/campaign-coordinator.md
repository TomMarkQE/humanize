# Native App campaign coordination

Use this protocol when a repository already defines a campaign's run files, candidate boundary, evaluator, and terminal decisions. The root Codex thread coordinates; the task package remains authoritative for workload, correctness, scoring, evidence fields, and promotion or no-go. This protocol introduces no `.humanize/rlcr` state beside task-owned state and needs no Stop hook or nested Codex CLI model process.

## Keep the root's working set small

At startup or after compaction, read the task's ownership map, current run state, current best and score, current attempt, and the task-specific contracts needed to choose the next mechanism. Read a prior round or raw log only when a current decision depends on it. Treat chat history as supplementary. The run's durable files must let a new coordinator reconstruct phase, candidate/base identity, results, unresolved blockers, and next action without replaying a transcript.

Before each attempt, fix one falsifiable mechanism hypothesis, its candidate/base identity, frozen workload and correctness boundary, deciding metric, and evidence location in the task-owned round record. Spawn a **fresh** bounded Implementer with `fork_turns: "none"` and a unique task name. Pass exact paths and the current attempt contract, not the coordinator's conversation. Use actual `model` and `reasoning_effort` spawn fields only for an explicit invocation or project-level choice; otherwise omit both to inherit the runtime choice. If requested fields are unavailable, report the capability block. Do not make a model choice a Humanize default.

The Implementer owns the attempt's code and local compile, test, and bounded tuning retries in its run-owned worktree. It records failed rows and diagnostic evidence as well as successes. Retry the same mechanism inside that child while the attempt contract still holds; a new mechanism gets a new child. The coordinator retains the hypothesis, current best, and promotion decision. Run only one writer against a worktree at a time.

After the candidate has evaluable evidence, spawn a **fresh** read-only Reviewer with `fork_turns: "none"`. Give it the original code and task contracts, fixed base, candidate diff, evaluator commands, and evidence paths; require independent verification of correctness, benchmark comparability, and claimed impact. Do not substitute the Implementer's narrative for inspection. Spawn a bounded Profiler only when a named uncertainty can change the next edit; it reports observations and evidence paths, not a new candidate or promotion decision. Reviewers do not edit candidate or run-state files. A Profiler may create raw, untracked logs and reports only in task-designated artifact paths; it never changes candidate code. The coordinator alone persists round result/decision files and updates run state or the scoreboard.

## Evidence-linked handoff

Each child returns a compact decision record, usually 500–1000 tokens. This is a guideline for routine prose, never a reason to omit failures or critical identity. The record must identify:

- role, attempt, candidate/base commits or other exact candidate identity, and tested artifact;
- correctness oracle, result, and every failed case or row relevant to acceptance;
- performance workload and timing scope, baseline and candidate values with units, repetitions or variance when available, and resource effects relevant to the decision;
- changed files or inspected diff, unresolved issues, recommended next action, and exact paths to durable evidence.

The coordinator checks that the record agrees with task-owned files before updating state. Keep detailed logs and per-row results in those files and link them from the handoff; retrieve them only for a disputed claim, failure diagnosis, or next mechanism choice. Never truncate a failing row or silently collapse an unmeasured case into a pass. If a child fails before producing a complete record, preserve its last known candidate identity, error, and evidence path in the run's existing round/state files, then decide a bounded recovery from those files.

The task's existing state and scoreboard remain the only run truth. Record the review verdict and decision in its prescribed round files, retain rejected directions as evidence, and keep rejected code out of the retained candidate. Apply the task's own terminal gate; a compact summary or child verdict alone does not authorize promotion.
