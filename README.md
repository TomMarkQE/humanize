# Humanize

**Current Version: 2.0.0**

> Derived from the [GAAC (GitHub-as-a-Context)](https://github.com/SihaoLiu/gaac) project.

Humanize provides goal-driven implementation, independent review, and iterative correction workflows for Codex, Claude Code, and Kimi.

## Codex-native workflow

Humanize 2.0 makes the Codex path a native Agent/Sub-agent workflow. The current Codex task is the coordinator, while implementation, investigation, plan-alignment review, and final code review run in visible native child threads. Users can inspect those threads in Codex App, CLI, and IDE.

The Codex-native path does not launch `codex exec` or `codex review` from a shell and does not use a Stop hook to obtain model output. Its scripts are limited to deterministic work such as Git validation, state persistence, input checks, and reviewer-result parsing.

The loop still has the same product outcome:

1. A worker implements the current mainline objective and records test evidence.
2. A separate implementation reviewer checks the plan and acceptance criteria.
3. Findings return to another worker round until implementation is complete.
4. A separate code reviewer inspects the branch diff and emits blocking `[P0-9]` findings or passes it.
5. Humanize ends with an explicit complete, blocked, failed, or cancelled state.

## Provider behavior

| Provider | Orchestration | Model work visibility |
|----------|---------------|-----------------------|
| Codex | Native Skills plus native custom agents | Child agent threads are visible and openable in the current Codex task |
| Claude Code | Existing plugin commands, hooks, and optional Claude Agent Teams | Claude provider behavior is unchanged |
| Kimi | Existing installed Skill bundle and deterministic runtime | Kimi provider behavior is unchanged |

Claude Code and Kimi retain the legacy provider workflow for compatibility. The Codex installer does not install that hook-driven reviewer path.

## Install

### Codex

```bash
git clone https://github.com/PolyArch/humanize.git
cd humanize
./scripts/install-skills-codex.sh
```

This installs Skills under `~/.agents/skills`, custom agents under `~/.codex/agents`, and a deterministic runtime under the installed `humanize` Skill. It also removes stale Humanize-managed Codex Stop hooks and duplicate legacy Skill copies while preserving unrelated user hooks, agents, and Kimi-owned helper shims.

See [Install for Codex](docs/install-for-codex.md) for prerequisites, migration, verification, custom paths, failure states, and uninstall instructions.

### Claude Code

```text
/plugin marketplace add PolyArch/humanize
/plugin install humanize@PolyArch
```

See [Install for Claude Code](docs/install-for-claude.md).

### Kimi

```bash
./scripts/install-skills-kimi.sh
```

See [Install for Kimi](docs/install-for-kimi.md).

## Codex quick start

Ask Codex to use the installed Skill:

```text
Use $humanize-rlcr to implement docs/plan.md.
```

Review-only mode:

```text
Use $humanize-rlcr --review-only --base-ref main.
```

One-shot independent analysis:

```text
Use $humanize-consult to trace the authentication failure path and identify the safest fix.
```

During an RLCR run, the root task spawns `humanize_worker`, `humanize_implementation_reviewer`, `humanize_code_reviewer`, and, when needed, `humanize_researcher` child threads. The default Codex depth of one is sufficient because only the root coordinator delegates.

## Claude Code quick start

```text
/humanize:gen-plan --input draft.md --output docs/plan.md
/humanize:refine-plan --input docs/plan.md
/humanize:start-rlcr-loop docs/plan.md
```

## Documentation

- [Usage Guide](docs/usage.md) -- Provider-aware commands, lifecycle, states, and options
- [Install for Codex](docs/install-for-codex.md) -- Native Skills and custom-agent installation
- [Install for Claude Code](docs/install-for-claude.md) -- Claude plugin installation
- [Install for Kimi](docs/install-for-kimi.md) -- Kimi Skill installation
- [Bitter Lesson Workflow](docs/bitlesson.md) -- Project memory and legacy provider selector routing

## License

MIT
