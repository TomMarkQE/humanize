---
name: humanize
description: Route Humanize work on Codex to native visible subagents for implementation, independent review, planning, refinement, and consultation.
---

# Humanize for Codex

Humanize's Codex path uses the current Codex task as the root coordinator and native child threads for delegated model work.

Use `$humanize-gen-plan` to turn a Draft into a structured Goal Plan. Use `$humanize-refine-plan` for annotated-plan refinement. Use `$humanize-rlcr` for implementation plus independent review, or review-only convergence. Use `$humanize-consult` for one bounded independent investigation.

## Native execution guarantee

For Codex sessions:

- never launch `codex exec`, `codex review`, another `codex` process, or another model CLI from shell;
- never use a Stop hook to obtain model output;
- deterministic scripts may validate paths, inspect Git, persist state, and parse stable contracts, but they are not agents;
- the root coordinator is the only thread that delegates; child roles do not spawn descendants;
- every role receives a self-contained bounded prompt because custom-agent selection and explicit model overrides are incompatible with a full-history fork;
- effective child sandbox and approval behavior inherit from the live parent task after role selection;
- the worker is the only role behaviorally authorized to change repository files;
- researcher and reviewer roles are mandatory no-write contracts, not claims of a separately enforced sandbox. The coordinator records the current HEAD and non-Humanize working-tree status before such a child starts and verifies both are unchanged before integrating the result.

A no-write child that changes HEAD, the index, tracked files, or untracked non-Humanize files has violated its role contract. Do not integrate its result or advance workflow state; report the exact change and persist an `agent_failed` or `permission_denied` outcome as appropriate.

## Runtime model and effort selection

Humanize stores no subagent model or reasoning-effort defaults.

The invoking request may select overrides for one or more roles in ordinary language, for example:

```text
Use the current parent model for the worker.
Use <available-model> with <effort> for research and review subagents.
```

For each child:

- when no override is selected, omit `model` and `reasoning_effort` from `spawn_agent` so Codex inherits the live parent selection;
- when an override is selected, pass both values as actual `spawn_agent` fields, never only as prose in the child message;
- use a non-full-history fork: V2 uses `fork_turns: "none"` or a deliberately bounded positive turn count; V1 uses `fork_context: false`;
- never use `fork_turns: "all"` or `fork_context: true` together with `agent_type`, `model`, or `reasoning_effort`;
- verify the started child activity/metadata when exposed. If an explicit override is rejected or does not become effective, report the runtime capability error instead of pretending it worked.

No persistent config key, routing registry, or model policy may be added for this purpose.

## Runtime root

The installer hydrates the deterministic runtime root below:

```text
{{HUMANIZE_RUNTIME_ROOT}}
```

The Codex-native RLCR state machine is available at:

```bash
python3 "{{HUMANIZE_RUNTIME_ROOT}}/scripts/native-rlcr.py" --help
```
