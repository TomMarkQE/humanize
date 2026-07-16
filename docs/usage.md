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

Only the root thread delegates. This prevents recursive fan-out and works with the default subagent depth of one. Writing agents run sequentially; independent read-only research can run concurrently.

### Codex options

| Option | Meaning |
|--------|---------|
| `--max N` or `--max-rounds N` | Maximum total rounds; default 42 |
| `--base-ref REF` or `--base-branch REF` | Comparison base for final review |
| `--track-plan-file` | Fail if the source plan changes during the run |
| `--review-only` | Skip implementation and start with code review |
| `--skip-impl` | Migration alias for `--review-only` |

The native path does not accept `--codex-model`, `--codex-timeout`, `--agent-teams`, `--claude-answer-codex`, or `--yolo`. Current-session model, effort, sandbox, and approval settings apply to child agents.

### Codex lifecycle

The deterministic runtime stores state under `.humanize/rlcr/<run>/`. Initialization requires a clean non-Humanize working tree; an untracked source plan is the only allowed initial exception. A worker round must end with a new descendant commit, a clean non-Humanize working tree, a structured summary, and recorded test evidence. Per-loop file locks serialize state transitions. The implementation reviewer then returns:

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

### Codex failure handling

The native runtime fails closed and emits JSON errors with non-zero exits. Important states and reasons include:

- `agent_unavailable`: a required custom agent cannot be spawned;
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

This spawns one read-only `humanize_researcher` child thread. It replaces the former Codex-side use of `ask-codex.sh`.

## Planning Skills

Generate a structured plan:

```text
Use $humanize-gen-plan with --input draft.md --output docs/plan.md.
```

Refine a plan containing `CMT: ... ENDCMT`, `<cmt>...</cmt>`, or `<comment>...</comment>` annotations:

```text
Use $humanize-refine-plan with --input docs/plan.md.
```

The installed validators remain deterministic. Any research or interpretation that requires a model occurs in the current Codex task or a native child agent, not in a shell-launched model process.

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

In this provider path, Claude implements and the legacy reviewer scripts may call the Codex CLI. Optional `--agent-teams` remains Claude-only and requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. This behavior is not described or installed as Codex-native delegation.

Legacy RLCR options include `--codex-model`, `--codex-timeout`, `--push-every-round`, `--full-review-round`, `--skip-impl`, `--claude-answer-codex`, `--agent-teams`, `--skip-quiz`, and `--yolo`. See the command help in Claude Code for the full provider-specific contract.

## Kimi provider

Kimi installs the shared legacy Skill bundle through:

```bash
./scripts/install-skills-kimi.sh
```

The Kimi path retains the established deterministic setup and model-router behavior. It does not receive the Codex custom-agent overlay.

## Configuration

The existing four-layer configuration remains available to Claude Code and Kimi:

1. `config/default_config.json`
2. `~/.config/humanize/config.json`
3. `.humanize/config.json`
4. provider CLI flags

Keys such as `codex_model`, `codex_effort`, `bitlesson_model`, `provider_mode`, and `agent_teams` belong to those legacy provider workflows. They do not override a Codex-native child agent's current-session configuration.

Codex custom-agent defaults live in installed TOML files under `~/.codex/agents/`. Parent-session live overrides still take precedence at spawn time.

## Monitoring and evidence

Claude/Kimi users can continue using the shell monitor:

```bash
source <path-to-humanize>/scripts/humanize.sh
humanize monitor rlcr
humanize monitor skill
```

Codex-native users should use the Codex client to inspect active and completed child threads.  The `.humanize/rlcr/<run>/` directory is the durable state and evidence ledger, not an Agent UI.

## Migration summary

Humanize 2.0 makes every Codex installer entrypoint native. Installation removes old Humanize-managed Codex Stop hooks, duplicate `<CODEX_HOME>/skills` copies, and the managed model-selector shim while preserving unrelated user assets. The old shell reviewer is not retained as a Codex fallback. Claude Code and Kimi compatibility paths remain available.

See [Install for Codex](install-for-codex.md) for detailed migration, verification, troubleshooting, and uninstall steps.
