---
name: codex-humanizer-gen-plan
description: Generate a pure-Codex implementation plan from a draft while delegating bounded repository evidence collection and independent plan review to native Codex subagents.
---

# Codex Humanizer Generate Plan

Transform an exact Draft into a repository-grounded Goal Plan. The live Codex root thread owns requirements, user decisions, candidate-plan synthesis, evidence integration, and the final write.

The installer hydrates this runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Inputs and deterministic validation

Required arguments:

- `--input <draft.md>`
- `--output <goal-plan.md>`

Validate before model work:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/codex-humanizer-plan-io.py" gen \
  --input <draft.md> \
  --output <goal-plan.md>
```

Stop on a non-zero result. Never overwrite an existing output and never modify implementation files while generating the plan.

## Runtime child selection

A caller may select one model and reasoning effort globally or provide role-specific values for the repository researcher and plan reviewer.

- No explicit override: omit `model` and `reasoning_effort`.
- Explicit override: pass both as actual `spawn_agent` fields.
- V2: use `fork_turns: "none"` or a deliberately bounded positive count and a descriptive lowercase `task_name`.
- V1: use `fork_context: false`.
- Do not simulate a model choice in prompt text.

## Phase 1: root Draft analysis

Read the exact Draft. In the root thread, extract:

- goal and non-goals;
- hard requirements, preferences, and prohibited choices;
- quantitative metrics and whether each is a hard gate or directional target;
- unresolved external decisions;
- required output, compatibility, validation, migration, and failure behavior;
- candidate acceptance-criteria identifiers and a plan skeleton.

The Draft is authoritative human input. Clarifications may add precision but must not silently discard its requirements.

## Phase 2: bounded repository evidence

Create one read-only repository child only when relevance, ownership, feasibility, current implementation, tests, or constraints require broad independent reading. Do not delegate a tiny lookup the root can finish directly.

The child owns only:

1. mapping the Draft to current repository behavior;
2. locating relevant paths, symbols, tests, validation commands, dependencies, and ownership boundaries;
3. identifying conflicts, feasibility gaps, and missing repository facts;
4. returning evidence without writing the Goal Plan or changing repository state.

Before spawning, record branch, exact `HEAD`, and `git status --porcelain`. The child must not edit, commit, install dependencies, change branches, or create non-Humanizer files.

Require this result:

```markdown
## Relevance
relevant | not_relevant | uncertain

## Evidence
- `path[:line]` or symbol — observed fact and why it matters

## Existing Validation
- command or test path — behavior covered

## Scope and Ownership
- likely changed path — ownership reason

## Risks and Gaps
- contradiction, missing decision, feasibility risk, or uncertainty

## Plan Implications
- implications for ACs, boundaries, milestones, and sequencing
```

While it runs, the root must continue non-overlapping Draft analysis and plan-skeleton work. Do not immediately wait and do not repeat the delegated repository investigation.

Collect this child before the final relevance decision, affected-path decision, feasibility guidance, AC synthesis, or output write. Verify branch, `HEAD`, and worktree status still match the baseline before integrating its evidence.

## Phase 3: candidate Goal Plan

Build a complete in-memory candidate plan from the Draft, resolved user decisions, and verified repository evidence. Keep facts, inferences, and open decisions distinct.

The pure-Codex plan schema is:

```markdown
# <Plan Title>

## Goal Description

## Acceptance Criteria
- AC-1: ...
  - Positive Tests (expected to PASS):
  - Negative Tests (expected to FAIL):

## Path Boundaries
### Upper Bound (Maximum Acceptable Scope)
### Lower Bound (Minimum Acceptable Scope)
### Allowed Choices

## Feasibility Hints and Suggestions

## Dependencies and Sequence

## Task Breakdown
| Task ID | Description | Target AC | Tag (`coding`/`analyze`) | Depends On |

## Pending User Decisions
- DEC-1: ...
  - Context: ...
  - Available Options: ...
  - Tradeoffs: ...
  - Coordinator Recommendation: ...
  - Decision Status: `PENDING` or the resolved decision

## Implementation Notes
```

`coding` means a future Codex Humanizer worker objective. `analyze` means a bounded read-heavy question whose result is required before a dependent worker objective. Never assign work to Claude.

Do not include `## Claude-Codex Deliberation`, Claude/Codex position summaries, or claims of convergence between agents that did not perform the recorded interaction.

## Phase 4: fresh independent plan review

Before writing the output, create a fresh read-only plan-review child. It must receive the exact Draft path, candidate plan text or temporary path, verified repository evidence, unresolved decisions, and this review schema. It must not edit files or make product decisions.

Require:

```text
SCOPE_CONFLICTS:
MISSING_REQUIREMENTS:
AC_GAPS:
EVIDENCE_GAPS:
UNSAFE_ASSUMPTIONS:
REQUIRED_CHANGES:
OPTIONAL_IMPROVEMENTS:
USER_DECISIONS:
VERDICT: REVISE | ACCEPT | BLOCKED
```

The reviewer must inspect the Draft and load-bearing repository evidence directly. `ACCEPT` is invalid when a required Draft constraint, repository conflict, unverifiable AC, or unresolved safety decision remains hidden.

While it runs, the root must independently check identifier consistency, Draft coverage, path ownership, test-to-AC mapping, dependency ordering, and the exact user decisions that would block implementation.

Collect and integrate the review before writing. Apply `REQUIRED_CHANGES`, preserve justified rejections, and ask the user only for decisions that cannot be derived safely from the Draft or repository. After material revision, perform at most one fresh confirmation review. Do not run an open-ended model debate.

## Final write and report

Write the Goal Plan only after all required evidence and review results are integrated. Review the final document for:

- complete Draft coverage;
- stable AC/task/decision identifiers;
- valid `coding`/`analyze` tags;
- repository-grounded paths and validation commands;
- no legacy Claude/Codex deliberation section;
- explicit unresolved decisions;
- no implementation edits or premature RLCR start.

Report the output path, AC count, delegated roles used, unresolved decisions, and any capability blocker. Do not auto-start RLCR from this Skill.
