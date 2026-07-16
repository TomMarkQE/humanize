---
name: humanize-rlcr
description: Legacy provider RLCR entrypoint for Kimi and Claude-compatible installations. Codex installs use the native skill under codex/skills instead.
type: flow
user-invocable: false
disable-model-invocation: true
---

# Humanize RLCR Loop (Legacy Providers)

This Skill preserves the existing hook-driven RLCR workflow for Kimi and Claude-compatible provider installations. It is not the Codex-native Agent/Sub-agent implementation.

The Codex installer uses `codex/skills/humanize-rlcr/SKILL.md`, native custom agents, and `scripts/native-rlcr.py`. It does not install this Skill or the legacy reviewer hook.

## Runtime Root

The installer hydrates this Skill with an absolute runtime root path:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

All commands below assume `{{HUMANIZE_RUNTIME_ROOT}}`.

## Required Sequence

### 1. Setup

Start the legacy loop with:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/setup-rlcr-loop.sh" $ARGUMENTS
```

If setup exits non-zero, stop and report the error.

### 2. Work Round

For each round:

1. Read the current prompt from `.humanize/rlcr/<timestamp>/round-<N>-prompt.md`, or the active finalize prompt.
2. Implement the required changes.
3. Commit changes.
4. Write the required summary file:
   - normal phase: `.humanize/rlcr/<timestamp>/round-<N>-summary.md`;
   - finalize phase: `.humanize/rlcr/<timestamp>/finalize-summary.md`.
5. Stop or exit normally so the provider's installed hook can evaluate the round.
6. When the hook blocks exit, follow its returned instructions and continue.

## Deterministic and model boundaries

The legacy Stop hook performs deterministic state, branch, plan, task, Git-clean, summary, and iteration checks. It also starts the legacy external reviewer process. This behavior is retained only for compatible non-Codex provider paths.

Do not describe this hook or its background process as a Codex-native agent. In Codex, use the native Humanize Skill and visible child threads instead.

## Critical rules

1. Never manually edit `state.md`, `finalize-state.md`, or methodology-analysis state.
2. Never skip a blocked hook result by declaring completion manually.
3. Always use the generated prompt, summary, and review-result files as the legacy workflow source of truth.
4. Do not use this Skill as a fallback from a failed Codex-native subagent run.

## Legacy options

Pass these through `setup-rlcr-loop.sh`:

| Option | Description | Default |
|--------|-------------|---------|
| `path/to/plan.md` | Plan file path | Required unless `--skip-impl` |
| `--plan-file <path>` | Explicit plan path | - |
| `--track-plan-file` | Enforce tracked plan immutability | false |
| `--max N` | Maximum iterations | 42 |
| `--codex-model MODEL:EFFORT` | External legacy reviewer model and effort | config default |
| `--codex-timeout SECONDS` | External reviewer timeout | 5400 |
| `--base-branch BRANCH` | Base for review phase | auto-detect |
| `--full-review-round N` | Full alignment interval | 5 |
| `--skip-impl` | Start directly in review path | false |
| `--push-every-round` | Require push each round | false |
| `--claude-answer-codex` | Let the implementation provider answer open questions | false |
| `--agent-teams` | Enable Claude Code Agent Teams | false |
| `--yolo` | Skip quiz and enable automatic open-question answers | false |
| `--skip-quiz` | Skip the Plan Understanding Quiz | false |

`--agent-teams` remains Claude Code-specific and requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Usage

```bash
/flow:humanize-rlcr path/to/plan.md
/flow:humanize-rlcr --skip-impl
```

## Cancel

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/cancel-rlcr-loop.sh"
```
