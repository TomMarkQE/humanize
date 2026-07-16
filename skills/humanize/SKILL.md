---
name: humanize
description: Legacy Humanize provider bundle for Kimi and Claude-compatible installations. Codex uses the native overlay under codex/skills.
user-invocable: false
disable-model-invocation: true
---

# Humanize (Legacy Provider Bundle)

This shared Skill documents the existing Kimi and Claude-compatible runtime. Humanize's Codex distribution does not install this file; it installs `codex/skills/humanize/SKILL.md` and native custom agents instead.

The legacy provider workflow keeps the established RLCR loop, plan generation, plan refinement, one-shot consultation, Goal Tracker, and deterministic validation behavior. Its external reviewer calls and provider hooks are compatibility mechanisms, not Codex-native agents.

## Runtime root

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

## Workflows

### RLCR loop

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/setup-rlcr-loop.sh" path/to/plan.md
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/setup-rlcr-loop.sh" --skip-impl
```

After each implementation or fix round, update the Goal Tracker, commit the work, write the required summary, and stop normally so the installed legacy hook can evaluate the next transition.

Common legacy options include `--max`, `--base-branch`, `--full-review-round`, `--track-plan-file`, `--push-every-round`, `--codex-model`, `--codex-timeout`, `--skip-impl`, and Claude-only `--agent-teams`.

### Generate and refine plans

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-gen-plan-io.sh" --input draft.md --output plan.md
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/validate-refine-plan-io.sh" --input plan.md
```

Follow the installed `humanize-gen-plan` and `humanize-refine-plan` Skills after deterministic IO validation.

### One-shot legacy consultation

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/ask-codex.sh" "your question"
```

This command starts an external model CLI and remains available only in the legacy provider bundle. Codex users should use `$humanize-consult`, which creates a visible native researcher child thread.

## Goal Tracker principles

- Map mainline tasks to acceptance criteria.
- Keep the immutable goal and acceptance criteria stable after round zero.
- Record justified plan evolution explicitly.
- Separate blocking side issues from queued follow-up.
- Require independent evidence before marking outcomes verified.

## Provider boundary

Never present the legacy Stop hook, a shell process, or its log files as a Codex-native agent. Never use this bundle as a hidden fallback when native Codex delegation is unavailable. The native Codex workflow must report `agent_unavailable`, `permission_denied`, `cancelled`, or another explicit state instead.
