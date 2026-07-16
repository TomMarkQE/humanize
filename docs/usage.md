# Humanize Usage Guide

Humanize supports two provider architectures. Codex uses native Skills and visible native subagents. Claude Code and Kimi keep the existing hook/script provider workflow for compatibility.

## Codex-native RLCR

Start from a Codex App, CLI, or IDE task opened on the target repository:

```text
Use $humanize-rlcr to implement docs/plan.md.
```

Review-only mode:

```text
Use $humanize-rlcr --review-only --base-ref main.
```

The current Codex thread is the root coordinator. It delegates to separate native child threads:

1. `humanize_worker` implements or fixes one bounded mainline objective and commits it.
2. `humanize_implementation_reviewer` independently checks plan alignment, acceptance criteria, and test evidence.
3. `humanize_code_reviewer` independently reviews the branch diff and returns blocking `[P0-9]` findings or passes it.
4. `humanize_researcher` answers bounded read-only questions requested by the root coordinator.

Only the root thread delegates. This prevents recursive fan-out and works with a subagent depth of one. Writing agents run sequentially; independent read-only research may overlap only when questions and evidence scopes do not overlap.

### Codex options

| Option | Meaning |
|--------|---------|
| `--max N` or `--max-rounds N` | Maximum total rounds; default 42 |
| `--base-ref REF` or `--base-branch REF` | Fixed comparison base for final review |
| `--track-plan-file` | Fail if the source plan changes during the run |
| `--review-only` | Skip implementation and start with code review |
| `--skip-impl` | Migration alias for `--review-only` |

The native path does not use legacy `--codex-model`, `--codex-timeout`, `--agent-teams`, `--claude-answer-codex`, or `--yolo` flags. Sandbox and approval settings come from the live parent task. Child model and reasoning effort are selected in the current invocation.

### Runtime model and effort selection

Humanize stores no native child model or reasoning-effort default.

Inheritance:

```text
Use $humanize-rlcr to implement docs/plan.md. Let every child inherit the parent model and effort.
```

The coordinator must omit `model` and `reasoning_effort` from the corresponding `spawn_agent` calls.

Explicit override:

```text
Use $humanize-rlcr to implement docs/plan.md.
Use <available-model> with <effort> for research and review children.
Pass both as actual spawn_agent fields and use a non-full-history fork.
```

The selected values must appear in the real tool parameters, not only in the child prompt. With a custom `agent_type`, use `fork_turns: "none"` or a bounded positive turn count on multi-agent V2, or `fork_context: false` on V1. A rejected or unavailable override is an observable capability blocker; do not silently inherit, substitute another model, or launch a nested CLI.

### Codex lifecycle

The deterministic runtime stores state under `.humanize/rlcr/<run>/`. Initialization requires a clean non-Humanize working tree; an untracked source plan is the only allowed initial exception. A worker round must end with a new descendant commit, a clean non-Humanize working tree, a structured summary, and recorded test evidence. Per-loop file locks serialize state transitions.

The implementation reviewer returns:

```text
HUMANIZE_IMPLEMENTATION_REVIEW: continue|complete|blocked
MAINLINE_PROGRESS: advanced|stalled|regressed
```

`continue` starts another implementation round. `complete` moves to final code review. `blocked` stops automatic progress. Three consecutive stalled or regressed implementation reviews also block the run for replanning.

The code reviewer returns:

```text
HUMANIZE_CODE_REVIEW: changes_required|pass|blocked
```

Every blocking finding under `changes_required` must start with `[P0]` through `[P9]`. A `pass` response cannot contain an unresolved priority marker. Humanize reports complete only after the deterministic state machine accepts that independent `pass` result.

The coordinator must perform useful non-overlapping work while a child runs, must not duplicate the delegated task, and must collect and integrate every required child result before a dependent edit, plan/QA write, state transition, or final report.

### Codex failure handling

The native runtime fails closed and emits JSON errors with non-zero exits. Important states and reasons include:

- `agent_unavailable`: a required custom role or requested override cannot be used;
- `permission_denied`: inherited sandbox or approval policy blocks required work;
- `cancelled` or `interrupted`: the user or client stopped the workflow;
- `working_tree_dirty`: a worker left non-Humanize changes uncommitted;
- `review_contract_invalid`: reviewer output omitted or contradicted its stable marker;
- `tracked_plan_changed` or `plan_snapshot_changed`: plan immutability was violated;
- `branch_changed` or `history_rewritten`: the branch moved away from its starting branch or rewrote prior checkpoints;
- `state_corrupt` or `lock_unavailable`: deterministic state cannot be trusted or serialized safely;
- `max_rounds_exhausted`: the loop did not converge in its configured bound.

There is no hidden `codex exec` or `codex review` fallback. State files provide deterministic evidence; actual model work remains visible in native child threads.

### Native consultation

For a bounded independent analysis without the full loop:

```text
Use $humanize-consult to trace the authentication failure path and recommend the safest repair.
```

This creates one read-only `humanize_researcher` child thread. It replaces the former Codex-side use of `ask-codex.sh`.

## Planning Skills

Generate a structured plan:

```text
Use $humanize-gen-plan with --input draft.md --output docs/plan.md.
```

Refine a plan containing `CMT: ... ENDCMT`, `<cmt>...</cmt>`, or `<comment>...</comment>` annotations:

```text
Use $humanize-refine-plan with --input docs/plan.md.
```

The installed validators remain deterministic. Repository investigation may be delegated only when bounded independent evidence is useful. The root continues non-overlapping planning/comment work and joins the child before final scope, ACs, research-dependent edits, QA, convergence, or atomic writes.

Common refine options:

| Option | Meaning |
|--------|---------|
| `--output PATH` | Write a separate refined plan; default is in-place |
| `--qa-dir PATH` | QA ledger directory; default `.humanize/plan_qa` |
| `--alt-language LANG` | Generate a supported translated plan and QA variant |
| `--discussion` | Confirm ambiguous comment classifications with the user |
| `--direct` | Make minimal safe assumptions and record them in QA |

## Claude Code provider

Claude Code keeps its existing plugin commands and Stop-hook loop:

```text
/humanize:gen-plan --input draft.md --output docs/plan.md
/humanize:refine-plan --input docs/plan.md
/humanize:start-rlcr-loop docs/plan.md
/humanize:cancel-rlcr-loop
/humanize:ask-codex Review the error handling in src/api/
```

In this provider path, Claude implements and legacy reviewer scripts may call the Codex CLI. Optional `--agent-teams` remains Claude-only and requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. This behavior is unchanged and is not installed as Codex-native delegation.

Legacy RLCR options include `--codex-model`, `--codex-timeout`, `--push-every-round`, `--full-review-round`, `--skip-impl`, `--claude-answer-codex`, `--agent-teams`, `--skip-quiz`, and `--yolo`. See the command help in Claude Code for the full provider-specific contract.

## Kimi provider

Kimi installs the shared Skill bundle through:

```bash
./scripts/install-skills-kimi.sh
```

The Kimi path retains the established deterministic setup and model-router behavior. It does not receive the Codex custom-agent overlay.

## Configuration

The existing layered configuration remains available to Claude Code and Kimi:

1. `config/default_config.json`
2. `~/.config/humanize/config.json`
3. `.humanize/config.json`
4. provider CLI flags

Keys such as `codex_model`, `codex_effort`, `bitlesson_model`, `provider_mode`, and `agent_teams` belong to legacy provider workflows. They do not select a Codex-native child model or effort.

Codex native role TOML files define role instructions and sandbox intent, not model policy. Model and reasoning selection belongs to each live invocation and is represented directly in the child tool call when explicitly chosen.

## Monitoring and evidence

Claude/Kimi users can continue using the shell monitor:

```bash
source <path-to-humanize>/scripts/humanize.sh
humanize monitor rlcr
humanize monitor skill
```

Codex-native users should use the Codex client to inspect active and completed child threads. The `.humanize/rlcr/<run>/` directory is the durable state and evidence ledger, not an Agent UI.

## Migration summary

Every Codex installer entrypoint routes to the native bundle. Installation removes old Humanize-managed Codex Stop hooks, duplicate `<CODEX_HOME>/skills` copies, and a managed legacy selector shim while preserving unrelated assets and the Claude/Kimi provider paths. The shell reviewer is not retained as a Codex fallback.

See [Install for Codex](install-for-codex.md) for detailed migration, runtime override, forward-test, troubleshooting, and uninstall steps.
