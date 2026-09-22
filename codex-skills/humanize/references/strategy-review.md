# Independent strategy review

Protocol: `campaign_strategy_v1`

## Purpose and evidence boundary

Review whether the optimization strategy is sound and what should happen next. Executable validators own numerical pass/fail. Accept the supplied identity-matched machine gate as a premise; do not rerun accuracy, manually recalculate tolerances, reproduce every test row, demand additional seeds by habit, or rewrite the evaluator. A brief check of result status, coverage and candidate identity is navigation, not another audit.

If the result is missing, failed, mismatched or contradicted by a concrete observation, identify the exact artifact/field and route a focused issue to the executor. Do not promote the candidate, invent a pass, or turn a hypothetical edge case into an unbounded testing assignment. A concrete source-discovered defect is not suppressed: state its premise and one discriminating check, then return to strategy. Test execution remains the executor's job.

## Mandatory review prompt

The caller must fill the common assignment fields and include these instructions verbatim or without weakening their meaning:

```text
You are the independent strategy Reviewer for <cNNN>.
Your primary question is whether this mechanism and the proposed next action
advance the supplied Goal under the accepted Plan.

Use the supplied machine correctness receipt as the numerical verdict for its
matched candidate/config. Do not rerun accuracy or perform a second per-row
precision audit. Flag only concrete missing/mismatched/contradictory evidence
for the executor. Do not edit candidate, evaluator, plan or parent state.

Read decision-relevant source and performance/profile findings. Evaluate:
1. Goal progress: target gap versus progress over the best admissible candidate.
2. Hypothesis quality: what observation supports/falsifies the proposed cause?
   Did the experiment distinguish it from the strongest alternative?
3. Search quality: did the baseline already implement the idea; are we only
   polishing a weak starting design; is a structural alternative more promising?
4. Memory validity: did changed resource/dataflow/compiler prerequisites make
   an old rejection stale? Name the cheapest discriminator before closing it.
5. Next action: choose continue, repair, revert, pivot, diagnose, or bounded
   no-go proposal; explain why this beats the strongest competing action.

Do not demand proof of a unique cycle attribution when a narrower measured
claim is enough to choose the next experiment. Do not request another profile
unless its possible outcomes would change that choice. A rejected hypothesis
can be useful information; it is not automatically progress in the metric.

Return the compact Strategy Review format below. Review suggestions are not
new user requirements. Keep only decision-changing blockers; queue optional
cleanup. The parent must explicitly dispose of consequential findings before
dependent next-mechanism work.
```

## Strategy Review result

- Identity: task name, iteration, role, reviewed candidate/base and machine receipt path.
- Goal/AC progress: what changed relative to the target and the incumbent.
- Hypothesis verdict: supported, falsified, or inconclusive, with deciding evidence.
- Strategy findings: ID, blocking or advisory, specific evidence and effect on the next decision.
- Reconsideration: stale prerequisite/revisit trigger, or `NONE`.
- Recommended next action: one chosen action, strongest alternative, smallest experiment and falsifier.
- Feedback closure: prior finding IDs resolved or still open.
- Gate exceptions: `NONE` or one concrete issue returned to the executor; do not include a new numerical-analysis section.

The strategy verdict never overwrites the machine verdict. A speculative optimization idea is not a blocking correctness finding. Final review uses the same distinction and checks the whole search/termination decision instead of redoing all measurements.
