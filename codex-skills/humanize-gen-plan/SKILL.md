---
name: humanize-gen-plan
description: Generate a goal-faithful implementation plan with repository evidence and independent technical strategy criticism using native Codex children.
type: flow
user-invocable: false
disable-model-invocation: true
---

# Humanize Generate Plan for Codex

Protocol: `campaign_strategy_v1`

Transform the exact user draft into the existing Humanize schema. Preserve the user's Goal, non-goals, hard constraints, optimization preferences and authorization. Only the requested plan output may be written during planning; no implementation, commits or PRs. Existing accepted plans resume rather than regenerate.

Runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Validate input/output

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-gen-plan-io.sh" --input <draft.md> --output <plan.md>
```

Stop on nonzero status. Preserve validator exit codes and do not overwrite an existing output. Record repository HEAD and worktree status before any read-only child.

## Evidence and candidate plan

Root extracts Goal, non-goals, constraints, measurable success, hard requirements versus trends, and genuinely unresolved user decisions. For distributed repository facts, delegate one bounded read-only investigation: relevant implementation, current starting point, tests, commands, ownership and conflicts. The child returns Relevance, Evidence, Existing Validation, Scope and Ownership, Risks and Gaps, and Plan Implications with exact source pointers. Do not delegate a trivial direct read merely to create a role.

Root writes a candidate plan in context from the exact draft and evidence. Repository discovery is not independent technical criticism. For a substantive optimization plan, obtain criticism of this candidate before final synthesis; the same read-only evidence child may continue as critic, but it must see the candidate and critique the strategy, not author the final plan.

## Independent Plan Critic prompt

Name the task `c000_plan_critic` for an initial campaign. For a strategic revision, use the current durable iteration and a plan-critic purpose; do not renumber completed work. Pass a self-contained input containing the exact Goal/non-goals, draft and candidate plan, implementation starting point, relevant source/measurement pointers, authorization and read-only boundary.

```text
Critique the candidate plan independently. Do not merely confirm that files
and headings exist. Do not implement, commit, install dependencies, run GPU
validation, or decide numerical tolerances yourself.

Check fidelity to the user's Goal and hard constraints, the quality of the
starting implementation, missing requirements, unsupported assumptions,
strongest alternative strategy, expected source of improvement, smallest
falsifying experiment, feedback/replanning conditions, and whether each AC
has an observable outcome. Distinguish task success from process completion.
Use machine validation as the owner of numerical pass/fail.

Return:
GOAL_FIDELITY: preserved requirements and any actual deviations
CORE_RISKS: concrete assumptions affecting the optimization route
TECHNICAL_GAPS: repository-backed missing prerequisites
ALTERNATIVE_DIRECTIONS: strongest competing route and its trade-off
REQUIRED_CHANGES: only decision-changing plan defects
OPTIONAL_IMPROVEMENTS: non-blocking suggestions
DISCRIMINATING_EXPERIMENT: minimal next check and possible decisions
PENDING_USER_DECISIONS: only unresolved material choices, otherwise NONE
```

Root incorporates required corrections or gives an evidence-backed rejection. Use the same critic for targeted closure of unresolved strategic disagreement; do not create a ritual multi-round debate after the decision is resolved. Unresolved blockers prevent activation. Do not invent cross-model agreement or a second reviewer that never ran. A tiny fully specified non-strategic plan may omit criticism with an explicit reason.

## Native spawn and join

Use actual `task_name=cNNN_role_purpose`, V2 `fork_turns: "none"` or V1 `fork_context: false`. Omit model/effort without explicit caller/project selection; otherwise set actual fields. Missing required capabilities are reported, never faked through prompt text or nested CLIs. Root can prepare AC mapping and scope while the child reads, without duplicating its investigation.

Join before final scope, feasibility or acceptance synthesis. Confirm HEAD/worktree did not change through read-only work. A failed child is recorded; root may recover repository discovery, but may not claim independent strategy criticism by self-review.

## Output schema

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

Keep stable AC IDs and executable task-specific checks. The legacy Deliberation heading records actual critic identity, findings and disposition, not fictitious Claude/Codex participation. For task-owned App campaigns, include explicit Goal/Plan/feedback handoffs and per-mechanism independent strategy review from `humanize/references/campaign-coordinator.md`; the task owns machine acceptance and state. Preserve inherited candidate provenance and distinguish re-establishing measurements from reimplementing a kernel.

Review final paths, requirements, unresolved choices and role boundaries before writing the output. Numerical/performance evidence not yet collected remains pending; plan acceptance does not claim measured success.
