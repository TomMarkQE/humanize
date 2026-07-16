# Humanize

**Current Version: 1.16.0**

> Derived from the [GAAC (GitHub-as-a-Context)](https://github.com/SihaoLiu/gaac) project.

Humanize provides goal-driven implementation loops with independent AI review for Claude Code, Codex, and Kimi.

## What is RLCR?

**RLCR** stands for **Ralph-Loop with Codex Review**, inspired by the official ralph-loop plugin. It is an iterative cycle in which implementation evidence is independently reviewed and blocking findings feed the next bounded round.

## Core concepts

- **Iteration over perfection** — make bounded progress, verify it, and refine.
- **Independent review** — implementation claims are checked against repository evidence and acceptance criteria.
- **Begin with the end in mind** — the user remains the architect of the Goal Plan.
- **Provider-specific orchestration** — Claude/Kimi retain their existing hook-driven workflow; Codex uses native child threads and keeps model selection at invocation time.

## Codex native workflow

The Codex install contains provider-specific skills:

- `$humanize-gen-plan` delegates bounded repository evidence collection to a read-only child.
- `$humanize-refine-plan` delegates repository-backed `research_request` comments to bounded read-only children.
- `$humanize-rlcr` makes the current root thread a coordinator for a writing worker, optional researcher, independent implementation reviewer, and independent fixed-base code reviewer.

The Codex runtime performs only deterministic state, Git, and atomic-write checks. It does not launch nested model processes or persist subagent model policy. Explicit child overrides are passed by the invoking root thread as actual `spawn_agent` fields; omitted overrides inherit the current runtime selection.

## Install

### Claude Code

```bash
/plugin marketplace add PolyArch/humanize
/plugin install humanize@PolyArch
```

See [Install for Claude Code](docs/install-for-claude.md).

### Codex

```bash
tmp_dir="$(mktemp -d)" && \
  git clone --depth 1 https://github.com/PolyArch/humanize.git "$tmp_dir/humanize" && \
  "$tmp_dir/humanize/scripts/install-skills-codex.sh"
```

The Codex installer migrates away from legacy Humanize-managed Stop hooks while preserving unrelated Codex hooks. See [Install for Codex](docs/install-for-codex.md).

### Kimi

See [Install for Kimi](docs/install-for-kimi.md).

## Quick start

Claude Code commands remain unchanged:

```bash
/humanize:gen-plan --input draft.md --output docs/plan.md
/humanize:refine-plan --input docs/plan.md
/humanize:start-rlcr-loop docs/plan.md
```

In Codex, invoke the corresponding installed skills:

```text
Use $humanize-gen-plan with --input draft.md --output docs/plan.md.
Use $humanize-refine-plan with --input docs/plan.md.
Use $humanize-rlcr to execute docs/plan.md.
```

Invocation-time child model and reasoning selections may be stated globally or per role. Humanize does not add permanent model defaults for native Codex subagents.

## Documentation

- [Usage Guide](docs/usage.md)
- [Install for Claude Code](docs/install-for-claude.md)
- [Install for Codex](docs/install-for-codex.md)
- [Install for Kimi](docs/install-for-kimi.md)
- [Bitter Lesson Workflow](docs/bitlesson.md)

## License

MIT
