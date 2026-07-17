# Codex Humanizer

**Current Version: 1.16.0**

> Derived from the Humanize project.

Codex Humanizer is a Codex-only fork of Humanize. It provides repository-grounded planning and a native Agent/Subagent implementation-review loop without launching nested `codex exec`, `codex review`, Claude Code, or Kimi processes.

The upstream Claude Code and Kimi workflows are maintained by the original Humanize project and are not installed or supported by this fork.

## Installed Skills

- `$codex-humanizer`: workflow overview and shared deterministic runtime.
- `$codex-humanizer-gen-plan`: generate a pure-Codex Goal Plan with bounded repository research and a fresh independent plan review.
- `$codex-humanizer-refine-plan`: refine annotated plans and produce a QA ledger.
- `$codex-humanizer-rlcr`: coordinate sequential implementation, optional research, implementation review, fixed-base code review, and finalization.

Skills are installed under:

```text
${CODEX_HOME:-~/.codex}/skills
```

The Python runtime is installed under:

```text
${CODEX_HOME:-~/.codex}/skills/codex-humanizer/scripts
```

## Install

```bash
tmp_dir="$(mktemp -d)" && \
  git clone --depth 1 https://github.com/TomMarkQE/humanize.git \
    "$tmp_dir/codex-humanizer" && \
  "$tmp_dir/codex-humanizer/scripts/install-skills-codex.sh"
```

From a checkout:

```bash
./scripts/install-skills-codex.sh
```

The installer keeps the historical `$CODEX_HOME/skills` location, installs only the Codex Humanizer Skills and their deterministic Python runtime, migrates this fork's previous `humanize-*` native installation when it can verify its signature, and removes stale Humanize-managed Codex Stop-hook entries without enabling new hooks.

Restart Codex after installation or upgrade so the renamed Skill metadata is reloaded.

## Verify

```bash
skills_root="${CODEX_HOME:-$HOME/.codex}/skills"

test -f "$skills_root/codex-humanizer/SKILL.md"
test -f "$skills_root/codex-humanizer-gen-plan/SKILL.md"
test -f "$skills_root/codex-humanizer-refine-plan/SKILL.md"
test -f "$skills_root/codex-humanizer-rlcr/SKILL.md"

python3 "$skills_root/codex-humanizer/scripts/native-rlcr.py" --help
```

## Quick Start

```text
Use $codex-humanizer-gen-plan with --input draft.md --output docs/goal-plan.md.
Review the generated Goal Plan.
Use $codex-humanizer-rlcr to execute docs/goal-plan.md with --base-ref main.
```

Refine a commented plan when needed:

```text
Use $codex-humanizer-refine-plan with --input docs/goal-plan.md.
```

Pure-Codex Goal Plans do not contain a `Claude-Codex Deliberation` section. Independent repository research and plan review are real native child tasks, but their branding is not written into the plan as fictional model positions.

## Runtime Model and Reasoning Selection

Codex Humanizer stores no subagent model or reasoning-effort defaults.

- Without an override, the root omits `model` and `reasoning_effort` so each child inherits the current runtime selection.
- With an explicit override, the root passes both as actual `spawn_agent` fields.
- Explicit overrides use a non-full-history fork: `fork_turns: "none"` or a bounded count on V2, or `fork_context: false` on V1.
- A model name written only inside a child prompt is not an override.

Example:

```text
Use $codex-humanizer-rlcr to execute docs/goal-plan.md.
Use the current runtime selection for the worker.
For research and both reviewers, use <available-model> with <effort>.
Pass each explicit choice as actual spawn_agent model and reasoning_effort fields.
```

## Mechanism

The live Codex root thread owns orchestration and decisions. Native children perform bounded work:

```text
root coordinator
  -> optional read-only researcher
  -> sequential writing worker
  -> fresh implementation reviewer
  -> fresh fixed-base code reviewer
  -> finalization
```

The bundled Python runtime does not call a model. It owns deterministic path, Git, state, result-schema, fixed-base, immutable-plan, and atomic-write checks under `.codex-humanizer/`.

See [Codex installation](docs/install-for-codex.md) and [usage](docs/usage.md).

## License

MIT
