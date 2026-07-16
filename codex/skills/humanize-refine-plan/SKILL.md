---
name: humanize-refine-plan
description: Refine an annotated Humanize plan and QA ledger while delegating bounded research_request comments to native Codex researcher children.
---

# Humanize Refine Plan for Codex

Refine an annotated plan without implementing repository code. Preserve the existing Humanize plan schema, comment semantics, QA ledger, alternate-language behavior, and atomic write transaction. The root thread owns parsing, classification, plan edits, consistency, convergence, QA generation, and final writes. Native researchers may own bounded behaviorally no-write `research_request` work. Effective child permissions inherit from the live parent task, so the root verifies repository state before integrating research.

The installer replaces `{{HUMANIZE_RUNTIME_ROOT}}` with the installed deterministic runtime path.

## Inputs and output ownership

Required:

- `--input <annotated-plan.md>`

Optional:

- `--output <refined-plan.md>`; default is in-place refinement;
- `--qa-dir <dir>`; default `.humanize/plan_qa`;
- `--alt-language <language-or-code>`;
- exactly zero or one of `--discussion` and `--direct`.

Permitted writes are only the refined plan, QA document, and requested language variants. Do not start RLCR, edit implementation files, commit, or create permanent research reports.

Run the existing validator with only its accepted arguments:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-refine-plan-io.sh" --input <input> [--output <output>] [--qa-dir <dir>] [--discussion|--direct]
```

Do not pass `--alt-language` to the validator. Load defaults through the installed config loader; add no delegation or model configuration keys.

## Preserve existing parsing and classification

Use a stateful scanner, not a naive global regular expression. Support inline and multiline forms of:

- `CMT:` ... `ENDCMT`;
- `<cmt>` ... `</cmt>`;
- `<comment>` ... `</comment>`.

Ignore markers in fenced code and HTML comments. Preserve surrounding non-comment text. Record document-order `CMT-N` IDs, source location, nearest heading, original text, normalized text, form, and context. Nested blocks, stray/mismatched end markers, and unterminated blocks are fatal with line, column, heading, and context.

Classify each raw comment as exactly one dominant type:

- `question`;
- `change_request`;
- `research_request`.

When a block contains multiple actions, create ordered processing sub-items while retaining one raw QA row. Dominant precedence is `research_request`, then `change_request`, then `question`. In discussion mode ask only the minimum unresolved classification or decision question. In direct mode use the smallest safe assumption and record it.

## Research delegation boundary

A `research_request` qualifies for delegation when it requires repository facts and can run independently while the parent processes other comments. Create separate children only for genuinely independent questions; group comments that require the same evidence.

Keep work local when the fact is already available, trivial, immediately blocking and faster to inspect directly, or tightly coupled to final plan synthesis. Never delegate ordinary questions, requested text edits, classification, convergence, QA synthesis, or atomic writes.

## No-write baseline

Before spawning the first researcher, record the current branch, exact `HEAD`, staged/unstaged tracked-file status, and untracked non-Humanize files. Preserve any existing dirty state exactly. The parent may continue parsing, classifying, answering comments, and preparing plan/QA content in memory, but must not write repository output or mutate implementation files while a research child is active.

Each researcher prompt must prohibit changing files, the index, branches, commits, or untracked non-Humanize state. This is a mandatory behavioral contract, not a claim of separate hard sandbox isolation.

## Runtime-selected spawn contract

Humanize defines no default model or reasoning effort.

For each `humanize_researcher` child:

- inheritance: omit `model` and `reasoning_effort`;
- explicit invocation-time override: pass both as actual `spawn_agent` fields;
- V2: use `task_name`, `message`, `agent_type: "humanize_researcher"`, and `fork_turns: "none"` or a deliberately bounded positive turn count;
- V1: use `message`, `agent_type: "humanize_researcher"`, and `fork_context: false`;
- never combine full-history fork with `agent_type`, `model`, or `reasoning_effort`.

If an explicit model or effort is unavailable, report the runtime error; do not silently substitute. A model name written only in the child prompt does not satisfy the override.

## Child task and required evidence

Give the child only the relevant `CMT-N` items, the unmodified source-plan context needed to understand them, repository paths and source boundaries, and the exact decision the evidence must support. Require no-write behavior and this result shape:

```text
COMMENT_IDS: CMT-N[, ...]
CONCLUSION: decision-relevant answer
FILES_AND_SYMBOLS_EXAMINED: repository-relative evidence
OBSERVED_BEHAVIOR: facts, tests, commands, or configuration
PLAN_IMPACT: exact section or requirement affected, or no_change
REMAINING_DECISION: none or a precise human choice
UNCERTAINTY: missing evidence
```

The child must not edit the plan, generate QA prose, implement code, or broaden the investigation.

## Parent work while research runs

Before joining children, the parent must continue non-overlapping work:

1. Finish extraction and classification of all comments.
2. Answer independent `question` items.
3. Prepare in-memory `change_request` edits that do not depend on research.
4. Build the cross-reference/consistency map for ACs, task IDs, dependencies, routing tags, pending decisions, and convergence.
5. Prepare the QA ledger rows and mark the research-dependent fields as pending.

Do not duplicate delegated research. Wait only when its evidence becomes necessary for the next plan edit or final transaction. Do not write final outputs while any required researcher is active.

## Integration and resolution

Before applying any research-dependent edit, completing `Research Findings`, deciding convergence, validating the final plan, or writing output:

- collect every required child result;
- compare the current branch, `HEAD`, index, tracked-file status, and untracked non-Humanize set against the recorded baseline;
- reject every child result associated with an unexplained repository-state change, report the exact delta, and do not restore or discard changes automatically;
- verify load-bearing repository citations only after the no-write baseline matches;
- integrate only conclusions supported by evidence;
- preserve unresolved material choices as `DEC-N` pending decisions;
- record child failure, local takeover, insufficient evidence, or a no-write violation in QA.

Every raw comment ends with one disposition: `answered`, `applied`, `researched`, `deferred`, or `resolved`. No final plan or QA may claim research completion before its evidence is collected, baseline-verified, and integrated.

## Plan and QA validation

Starting from the source plan with comment blocks removed, apply accepted refinements and retain the existing required sections, identifiers, optional sections, and original-Draft appendix. Keep routing tags exactly `coding` or `analyze` when present. Propagate every AC/task/dependency change across all references.

Before writing, verify:

- all required sections remain;
- no valid comment marker remains;
- every referenced AC and task exists;
- dependencies reference existing task IDs or `-`;
- pending decisions and convergence agree;
- main language is consistent;
- QA contains exactly one ledger row per raw `CMT-N`, plus answers, research findings, plan changes, remaining decisions, and metadata.

Prepare the refined plan, QA, and all variants completely before writing. Write temporary sibling files, fsync where supported, and atomically replace destinations only after every content and translation step succeeds. On failure, remove temporary files and leave existing outputs unchanged.

Report output paths, counts by classification/disposition, delegated research status, modified sections, and final convergence state.
