# Native App goal and strategy feedback

Protocol: `campaign_strategy_v1`

Use this protocol when the task owns run files, candidate boundaries, executable evaluation, and final acceptance. Humanize owns the reusable Goal/Plan/independent-feedback contract; the task supplies numerical semantics, workload, scoring, Git identities, artifact paths and promotion rules. One native parent executes both responsibilities using the task's existing state. Do not create a second `.humanize/rlcr` state, Stop hook, nested model CLI, or separate scheduler.

## Goal and Plan

Preserve the original Goal, hard constraints versus optimization preferences, non-goals, acceptance criteria and uncertainty. For a substantive new plan or strategic revision, obtain independent technical criticism, not merely repository-path discovery. The critic checks the starting implementation, expected source of improvement, strongest alternative, discriminating experiment, plan coverage and unsupported assumptions. The parent resolves required changes before activation; only genuinely unresolved material user choices require alignment. An accepted plan resumes without regeneration. New evidence may change strategy, not silently rewrite frozen semantics or scoring.

## Native assignments and ownership

The parent owns the goal gap, current incumbent, direction ranking, assignments, feedback disposition and final task decision. Execution children own code, compilation, evaluator calls, profiling analysis and coherent retries. A separate Profiler is optional, not required for each Skill. On a Remote Connection host, pass the actual host context, absolute worktree/cwd and available command tools; a desktop SSH label is metadata, not another hop.

Name every actual native task `cNNN_role_purpose`. `c000` is preparation or inherited checkpoint establishment; `c001` starts the first new mechanism. The number denotes the durable task iteration, not the number of child calls. Same-iteration implement/review/profile roles share the number. Local repair and re-review reuse their children; replacement instances use `_a02`, retain the original iteration and explicitly inherit feedback. The task records native agent IDs next to the names in its existing round record. Never renumber history after invalidation.

Use non-full-history spawns: V2 `fork_turns: "none"`, V1 `fork_context: false`. Honor caller/project model and effort through actual spawn fields; otherwise inherit. Missing requested fields are a capability block, not permission to impersonate another model. Children must not create an untracked delegation tree.

Every input must explicitly contain:

- Goal and non-goals; Plan path/version and relevant AC requirements, not just identifiers;
- current target gap, validated incumbent, active exploration and latest decision;
- the local decision/outcome and why it advances the Goal;
- exact candidate/base, host/worktree, evidence paths and allowed/protected writes;
- prior review findings to resolve, or explicit `NONE`;
- hypothesis, strongest alternative, changed prerequisites and supporting/falsifying observations where applicable;
- applicable executable validation, return boundary, role-owned report and requested next-step recommendation.

Do not copy full logs/history. Recover only decision-relevant context. Parent uses concise updates and waits, not duplicate validators or raw-result polling. Each child writes its own report; parent links it rather than transcribing it.

## Mechanism execution and independent strategy review

Use one falsifiable mechanism per durable iteration. Machine-searchable parameters, build fixes and coherent diagnosis remain inside it. A fresh Implementer normally starts a new mechanism; the task may preserve a coherent executor across explicitly bounded assignments, but cannot hide a new mechanism inside an old iteration or skip its review.

Execution must satisfy the task's complete executable correctness gate before speed ranking. Code repairs refresh the applicable gate; the retained configuration satisfies the full final gate. These checks belong to code and the execution child, not to the strategy Reviewer.

Every completed mechanism, including a rejected mechanism or attempted local exit, receives one independent strategy review under [strategy-review.md](strategy-review.md). Do not demand a review for each compile retry, parameter trial, or evidence-only command. The same Reviewer handles feedback closure for that iteration. A final review covers the whole retained strategy/no-go claim; it does not duplicate numerical testing.

Before review, save the candidate snapshot and machine result. Review may coexist with non-dependent read-only preparation, but not with next-mechanism implementation that depends on an unresolved strategy decision. Keep one writer and serialize GPU work. Missing/failed validation permits discussion of a next diagnostic action, never candidate acceptance or performance ranking.

## Feedback disposition

The Reviewer returns specific findings, the highest-value next action and its falsifier. The parent records each consequential finding as implemented, evidenced rejection, or deferred with a concrete prerequisite. Routine non-blocking suggestions may be queued. An open blocking finding cannot be silently dropped, overwritten by a parent verdict, or bypassed by changing the child's name.

Send accepted changes and remaining findings directly in the next assignment. Repair and re-review stay in the same iteration. A new strategy gets a new iteration after disposition. A new model/session must inherit the same Goal, Plan and unresolved findings.

## Search memory and Git

Retain an immutable candidate code identity before formal measurement, and bind results to source/build/config/workload/timing. Store candidate code and evidence as separate commits when necessary to avoid self-referential hashes. Keep best admissible implementation separate from external reference and active exploration. A correct slower candidate can support a bounded experiment but cannot replace the incumbent.

For each rejected direction, retain its source/resource prerequisite, observed result, validity context, revisit trigger and cheapest discriminator. When dataflow, register/shared-memory limits, compiler behavior or geometry changes, flag dependent negative conclusions for reconsideration. Reopening a prerequisite does not assert that the design will win.

Do not conflate target gap with candidate-lineage progress. Record both; the task owns exact counters. Recovering or correcting evidence cannot erase the fact an experiment happened. No telemetry or new behavior-test framework is required by this protocol.

## Completion

Continue when the next bounded experiment has a credible basis. Promotion requires machine-validated task acceptance plus resolved strategy feedback; whole-task no-go requires current limitations and concrete reasons the strongest remaining alternatives are low-yield or outside scope. Neither correct-but-slower code nor a completed checklist is an optimization success. A budget stop is pause/replan, never automatically no-go. Preserve incumbent, evidence, unresolved feedback and next action.
