---
name: humanize-refine-plan
description: Refine an annotated Humanize plan while delegating repository-backed research requests to bounded native read-only Codex subagents.
type: flow
user-invocable: false
---

# Humanize Refine Plan for Codex

Refine a plan containing `CMT:` / `ENDCMT` blocks into the existing comment-free plan and QA ledger. Preserve the gen-plan schema, comment ownership, convergence semantics, and atomic-write behavior.

The installer hydrates this runtime root:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

Validate first:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-refine-plan-io.sh" --input <annotated-plan> [--output <refined-plan>] [--qa-dir <qa-dir>] [--discussion|--direct]
```

Do not pass `--alt-language` to the validator. Stop on parse or validation failure.

## Parse and classify in the root thread

The root thread must use the existing stateful comment scanner, assign one stable `CMT-N` identifier per raw block, and classify each block as exactly one of:

- `question`
- `change_request`
- `research_request`

Resolve ambiguity according to `--discussion` or `--direct`, and record the decision in QA.

## Delegation boundary for `research_request`

Create a read-only child only when a `research_request` requires current repository facts. Group comments only when they share the same code path or evidence set; otherwise use independent bounded children.

Each child owns only the listed `CMT-N` items. It must not answer unrelated comments, rewrite the plan, edit files, commit, or make product decisions.

### Required child result

```markdown
## Comments Covered
- CMT-N

## Findings
### CMT-N
Conclusion: ...
Evidence:
- `path[:line]` — observed fact
Checked:
- file, symbol, test, or command
Plan Implication: ...
Remaining Uncertainty: none | ...
User Decision Required: no | ...

## Cross-Comment Conflicts
- none | conflict and affected CMT identifiers
```

A finding without repository evidence is incomplete. The child must distinguish observed facts from inference.

## Spawn requirements

Pass a self-contained prompt with the exact comments, plan path, repository root, read-only rules, and result schema.

- V2: `fork_turns: "none"` plus a unique `task_name`.
- V1: `fork_context: false`.
- No explicit override: omit `model` and `reasoning_effort`.
- Explicit override: pass both as actual `spawn_agent` fields; prompt wording alone is not sufficient.

Record `HEAD` and `git status --porcelain` before each read-only delegation.

## Root work while research runs

The root must continue useful, non-overlapping work:

- finish extracting and classifying all comment blocks;
- answer `question` items that do not require repository research;
- apply independent `change_request` items to an in-memory plan draft;
- prepare one QA row per raw `CMT-N`;
- build the plan-reference and identifier consistency map;
- prepare translated-variant metadata when requested.

Do not repeat the delegated repository research.

## Join and integration point

Collect all required research before:

- applying any `research_request` disposition to the plan;
- filling QA `Research Findings` or `Remaining Decisions` fields;
- deciding convergence;
- final schema validation;
- writing any output.

Verify `HEAD` and worktree state match the pre-spawn snapshot. A child that changed repository state has violated the contract and its result must not be integrated until the violation is handled.

If a child fails, the root may perform the same bounded research itself, but must record the failure and resulting evidence in QA.

## Preserved output guarantees

The refined plan must:

- preserve required gen-plan sections and optional appendices;
- remove all resolved comment markers;
- keep routing tags restricted to `coding` or `analyze`;
- keep identifiers and cross-references consistent;
- preserve approved scope and unresolved user decisions;
- write the refined plan, QA ledger, and language variants atomically through temporary files and rename;
- leave all original files unchanged when any output validation or write fails.

The QA ledger must retain one row per raw comment and record classification, disposition, answer, research evidence, applied change, remaining decision, and convergence status.
