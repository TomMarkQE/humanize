---
name: humanize-gen-plan
description: Generate a structured implementation plan from a Draft while delegating bounded repository investigation to a native Codex researcher when it can run independently.
---

# Humanize Generate Plan for Codex

Generate the requested Goal Plan without implementing repository changes. The current Codex thread owns requirements, decisions, synthesis, validation, and the final write. A native `humanize_researcher` child may own bounded read-only repository investigation.

The installer replaces `{{HUMANIZE_RUNTIME_ROOT}}` with the installed deterministic runtime path.

## Inputs and writes

Required arguments:

- `--input <draft.md>`
- `--output <plan.md>`

Preserve supported `--discussion`, `--direct`, `--auto-start-rlcr-if-converged`, and configured alternate-language behavior from the Humanize planning workflow. Before any optional RLCR start, permitted writes are limited to the requested plan and configured translated variant. Never modify the Draft, source code, run experiments, commit, or create implementation artifacts.

Run the existing validator exactly:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-gen-plan-io.sh" --input <input> --output <output>
```

Honor its existing exit codes and template path. Load Humanize configuration through the installed `scripts/lib/config-loader.sh`; do not invent new model, delegation, or planning config keys.

## Decide whether to delegate

Create one `humanize_researcher` child only when repository evidence is materially needed and the investigation can run while the parent performs useful independent planning work. Typical triggers are:

- relevance or affected scope cannot be established from already-read authoritative inputs;
- the Draft depends on existing implementation, tests, ownership, integration seams, or feasibility facts spread across multiple files;
- an assumption needs read-heavy verification before it can safely become an acceptance criterion or task.

Do not delegate a trivial lookup, an immediately blocking fact that the parent can read faster, final plan synthesis, user-decision resolution, or output validation. Do not duplicate the delegated investigation.

## Runtime-selected spawn contract

Humanize pins no model or effort.

When spawning the researcher with no explicit invocation-time override, omit `model` and `reasoning_effort`. When the invoking request selects an override, pass the selected values as actual `spawn_agent` fields. Use the runtime's exposed shape:

- V2: `task_name`, `message`, `agent_type: "humanize_researcher"`, and `fork_turns: "none"` or a deliberately bounded positive turn count;
- V1: `message`, `agent_type: "humanize_researcher"`, and `fork_context: false`.

Never use a full-history fork with `agent_type`, `model`, or `reasoning_effort`. Mentioning a model only inside the child message is not an override. If an explicit selection is unavailable or rejected, report the capability error; do not silently inherit or choose another model.

## Bounded researcher task

The child prompt must be self-contained and include:

- the Draft path and the exact decision-relevant Draft content;
- repository root and allowed read scope;
- authoritative repository instructions and source boundaries;
- the precise questions the plan needs answered;
- explicit read-only and non-implementation boundaries;
- the required return schema below.

Require:

```text
RELEVANCE: relevant|not_relevant|uncertain, with reason
CURRENT_IMPLEMENTATION: paths, symbols, and observed behavior
AFFECTED_SCOPE: likely files, tests, interfaces, and owners
CONSTRAINTS_AND_INVARIANTS: evidence-backed boundaries
RISKS_AND_GAPS: contradictions, missing requirements, feasibility risks
CANDIDATE_TESTS: evidence-backed positive, negative, and regression checks
OPEN_UNCERTAINTY: facts not established
```

Every material claim must cite a repository-relative path, symbol, command, or authoritative source. Generic advice and final plan prose are out of scope.

## Parent work while the child runs

Before collecting the child, the parent must make visible progress on non-overlapping work:

1. Extract the Draft's goal, non-goals, protected boundaries, metrics, and explicit decisions.
2. Separate established facts from assumptions and unresolved user choices.
3. Prepare the plan skeleton and initial AC/task candidates based only on known inputs.
4. Identify exactly which skeleton fields depend on delegated evidence.

Do not call the wait tool immediately unless no useful parent work remains. Do not repeat the repository investigation.

## Integration gate

Collect the child before making the final relevance decision, freezing affected scope, finalizing acceptance criteria, or writing the plan. Verify critical citations directly. Mark unsupported claims as uncertainty rather than converting them into requirements.

A child failure may be handled locally only when the parent can complete the same bounded research from available evidence. State the takeover and reason. If the missing evidence blocks a safe plan, stop without writing a false-complete plan.

## Plan output contract

Generate the existing Humanize plan schema and preserve authoritative Draft overrides. The plan must contain the execution-relevant form of:

- Goal Description;
- Acceptance Criteria using `AC-X` identifiers with meaningful positive and negative tests;
- Path Boundaries, protected files, allowed and prohibited choices;
- Feasibility Hints and Suggestions;
- Dependencies and Sequence;
- Task Breakdown with valid `coding` or `analyze` routing tags when the active template requires them;
- Pending User Decisions only for real unresolved choices;
- Implementation Notes and any required source-Draft appendix.

If an authoritative Draft contract forbids legacy Claude/Codex deliberation language or narrows the schema, follow that contract. Do not claim agents deliberated unless they actually did.

Resolve cross-references, dependency IDs, AC mappings, language consistency, and internal contradictions before writing. Write the final plan only after all required child evidence has been integrated. Report the output path, AC count, delegated research status, and unresolved decisions.
