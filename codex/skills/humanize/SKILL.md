---
name: humanize
description: Route Humanize work on Codex to native visible subagents for implementation, independent review, planning, and consultation.
---

# Humanize for Codex

Humanize is an iterative, goal-driven workflow built on Codex's native subagent orchestration.

Use `$humanize-rlcr` when the user wants implementation plus independent feedback, or review-only convergence on the current branch. Use `$humanize-consult` for a bounded second opinion or repository investigation. Use `$humanize-gen-plan` and `$humanize-refine-plan` for plan authoring workflows.

## Codex-native guarantee

For Codex sessions:

- model-backed work belongs to the current task's native agent hierarchy;
- implementation, research, and review are delegated to installed custom agents;
- users can inspect the resulting child threads in Codex App, CLI, and IDE;
- Humanize does not start `codex exec`, `codex review`, or another model CLI from a shell;
- Humanize does not use a Stop hook to obtain model output;
- deterministic scripts may validate paths, inspect Git, persist state, and parse stable result contracts, but they are not agents.

The legacy shell-driven reviewer remains part of the Claude Code provider path only. It is not installed by the Codex-native installer.

## Routing

When a request includes a plan or asks to implement/fix/review until complete, follow `$humanize-rlcr` exactly.

When a request asks for an independent analysis without an implementation loop, follow `$humanize-consult` and spawn `humanize_researcher` in a visible native child thread.

When the request is only to create or refine a plan, use the corresponding planning skill. Any research delegated during planning must also use a native child agent rather than a model CLI script.

## Runtime

The installer hydrates the deterministic runtime root below:

```text
{{HUMANIZE_RUNTIME_ROOT}}
```

The native RLCR state machine is:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" --help
```

It never invokes a model. Do not substitute the legacy `setup-rlcr-loop.sh`, `ask-codex.sh`, or `loop-codex-stop-hook.sh` in a Codex-native task.
