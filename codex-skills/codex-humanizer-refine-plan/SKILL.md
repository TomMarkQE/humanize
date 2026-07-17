---
name: codex-humanizer-refine-plan
description: Refine an annotated pure-Codex Goal Plan into a comment-free plan and QA ledger while delegating repository-backed research requests to bounded native Codex subagents.
---

# Codex Humanizer Refine Plan

Refine an annotated Goal Plan containing `CMT:` / `ENDCMT`, `<cmt>` / `</cmt>`, or `<comment>` / `</comment>` blocks. Preserve the pure-Codex plan schema, stable comment ownership, convergence meaning, and atomic-write behavior.

The installer hydrates this runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Validation

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/codex-humanizer-plan-io.py" refine \
  --input <annotated-plan.md> \
  [--output <refined-plan.md>] \
  [--qa-dir <qa-dir>] \
  [--discussion | --direct] \
  [--alt-language <language-or-code>]
```

The default QA directory is `.codex-humanizer/plan_qa`. Stop on parse, schema, or path validation failure.

## Root parsing and classification

Use a stateful scanner that ignores markers inside fenced code and HTML comments. Assign one stable `CMT-N` identifier per non-empty raw comment block and classify it as exactly one of:

- `question`;
- `change_request`;
- `research_request`.

Resolve ambiguity according to `--discussion` or `--direct` and record the choice in QA. The root owns comment extraction, classification, all non-research decisions, plan editing in memory, identifier consistency, and final atomic writes.

## Bounded research delegation

Create a read-only child only when a `research_request` requires current repository facts. Group comments only when they share the same code path or evidence set.

Each child owns only the listed `CMT-N` items. It must not answer unrelated comments, rewrite the plan, edit files, commit, or decide product policy.

For every spawn:

- omit `model` and `reasoning_effort` for inheritance;
- when the caller explicitly selects an override, pass both as actual `spawn_agent` fields;
- use `fork_turns: "none"` or a deliberately bounded positive count on V2, or `fork_context: false` on V1;
- stop with a capability blocker rather than placing an unsupported override only in prompt text.

Record branch, `HEAD`, and `git status --porcelain` before each research child. Require:

```markdown
## Comments Covered
- CMT-N

## Findings
### CMT-N
Conclusion: ...
Evidence:
- `path[:line]` or symbol — observed fact
Checked:
- file, symbol, test, or command
Plan Implication: ...
Remaining Uncertainty: none | ...
User Decision Required: no | ...

## Cross-Comment Conflicts
- none | conflict and affected CMT identifiers
```

A finding without repository evidence is incomplete. The child must distinguish observation from inference.

## Root work while research runs

The root must continue useful, non-overlapping work:

- finish extracting and classifying all comments;
- answer independent `question` items;
- apply independent `change_request` items to an in-memory plan;
- prepare one QA row per raw `CMT-N`;
- build the identifier and cross-reference consistency map;
- prepare translated-variant metadata when requested.

Do not repeat the delegated research.

## Join and integration gate

Collect all required research before:

- applying a `research_request` disposition;
- filling QA research or remaining-decision fields;
- deciding convergence;
- final schema validation;
- writing the refined plan, QA ledger, or variants.

Verify branch, `HEAD`, and worktree status match the recorded baseline. A child that changed repository state has violated the contract; do not integrate its result until the exact delta is handled. If delegation fails, the root may perform the same bounded research but must record the failure and replacement evidence in QA.

## Preserved pure-Codex schema

The final plan must contain:

- `## Goal Description`;
- `## Acceptance Criteria`;
- `## Path Boundaries`;
- `## Feasibility Hints and Suggestions`;
- `## Dependencies and Sequence`;
- `## Task Breakdown`;
- `## Pending User Decisions`;
- `## Implementation Notes`.

It must not contain `## Claude-Codex Deliberation`, Claude/Codex position summaries, resolved comment markers, invalid routing tags, or inconsistent identifiers.

Pending decisions use `Context`, `Available Options`, `Tradeoffs`, `Coordinator Recommendation`, and `Decision Status`, not branded model positions.

## QA and atomic output

The QA ledger records one row per raw `CMT-N`, including classification, location, disposition, answer, research evidence, applied change, remaining decision, and convergence status.

Write the refined plan, QA ledger, and any translated variants through temporary files followed by atomic rename. If any final validation or write fails, leave the original plan and all existing outputs unchanged.
