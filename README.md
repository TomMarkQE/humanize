# Humanize

**Current Version: 1.16.0**

> Derived from the [GAAC (GitHub-as-a-Context)](https://github.com/SihaoLiu/gaac) project.

Humanize provides iterative development with independent AI review. Claude Code and Kimi retain the existing provider workflow; Codex can use a native root-coordinator and visible subagent workflow.

## What is RLCR?

**RLCR** stands for **Ralph-Loop with Codex Review**, inspired by the official ralph-loop plugin and enhanced with independent review. The name also reads as **Reinforcement Learning with Code Review** -- reflecting the iterative cycle where AI-generated code is continuously refined through external feedback.

## Core Concepts

- **Iteration over Perfection** -- Instead of expecting perfect output in one shot, Humanize uses continuous feedback loops where issues are caught early and refined incrementally.
- **Independent Review** -- Implementation and review are owned by separate model contexts.
- **Begin with the End in Mind** -- Before the loop starts, Humanize verifies that the plan and acceptance criteria are actionable. ([Details](docs/usage.md#begin-with-the-end-in-mind))
- **Provider Isolation** -- The Codex-native installation is separate from the existing Claude Code and Kimi workflow, so one provider path does not silently change another.

## How It Works

<p align="center">
  <img src="docs/images/rlcr-workflow.svg" alt="RLCR Workflow" width="680"/>
</p>

The workflow still converges through implementation, independent plan/alignment review, independent code review, and corrective rounds. On Codex, the current root task coordinates visible native children for implementation, bounded investigation, implementation review, and final code review. The Codex-native path does not launch nested `codex exec` or `codex review` processes and does not use a Stop hook to obtain model output.

## Install

### Claude Code

```bash
# Add PolyArch marketplace
/plugin marketplace add PolyArch/humanize
# If you want to use development branch for experimental features
/plugin marketplace add PolyArch/humanize#dev
# Then install humanize plugin
/plugin install humanize@PolyArch
```

See [Install for Claude Code](docs/install-for-claude.md). The existing Claude commands, hooks, model configuration, and optional Agent Teams behavior remain unchanged.

### Codex-native path

```bash
git clone https://github.com/PolyArch/humanize.git
cd humanize
./scripts/install-skills-codex.sh
```

This installs native Humanize Skills under `~/.agents/skills`, custom roles under `~/.codex/agents`, and a deterministic RLCR state runtime. It removes only Humanize-managed legacy Codex hooks and stale Humanize copies; it preserves unrelated user configuration and the Claude/Kimi provider paths.

After restarting Codex, use the Skills from the current repository task:

```text
Use $humanize-gen-plan with --input draft.md --output docs/plan.md.
Use $humanize-refine-plan with --input docs/plan.md.
Use $humanize-rlcr to implement docs/plan.md.
Use $humanize-consult to investigate one bounded repository question.
```

Subagent model and reasoning effort are selected at invocation time rather than stored in Humanize. When an explicit override is requested, the root coordinator must pass `model` and `reasoning_effort` as actual `spawn_agent` fields and use a non-full-history fork. When no override is requested, both fields are omitted so the child inherits the current parent selection.

Effective child permissions also inherit from the live parent task. The worker is the only Humanize role authorized to write repository files. Researcher and reviewer roles are behaviorally no-write; before their results are integrated, the coordinator verifies that branch, HEAD, index, tracked status, and untracked non-Humanize files still match the recorded baseline. Humanize does not claim that custom role TOML provides a separately enforced hard sandbox.

See [Install for Codex](docs/install-for-codex.md) for migration, verification, native roles, runtime states, no-write verification, and troubleshooting.

### Kimi

```bash
./scripts/install-skills-kimi.sh
```

See [Install for Kimi](docs/install-for-kimi.md). The Kimi provider bundle continues to use the existing shared Skills and runtime.

## Claude Code Quick Start

1. **Generate an idea draft** from a loose thought (optional — skip if you already have a draft):
   ```bash
   /humanize:gen-idea "add undo/redo to the editor"
   ```
   Output goes to `.humanize/ideas/<slug>-<timestamp>.md` by default. Pass a `.md` path to expand existing rough notes. `--n` controls how many parallel directions explore the idea (default 6).

2. **Generate a plan** from your draft:
   ```bash
   /humanize:gen-plan --input draft.md --output docs/plan.md
   ```

3. **Refine an annotated plan** before implementation when reviewers add comments (`CMT:` ... `ENDCMT`, `<cmt>` ... `</cmt>`, or `<comment>` ... `</comment>`):
   ```bash
   /humanize:refine-plan --input docs/plan.md
   ```

4. **Run the loop**:
   ```bash
   /humanize:start-rlcr-loop docs/plan.md
   ```

5. **Consult Gemini** for deep web research (requires Gemini CLI):
   ```bash
   /humanize:ask-gemini What are the latest best practices for X?
   ```

6. **Monitor progress (in another terminal, not inside Claude Code)**:
   ```bash
   source <path/to-humanize>/scripts/humanize.sh
   humanize monitor rlcr
   humanize monitor skill
   humanize monitor codex
   humanize monitor gemini
   ```

## Monitor Dashboard

<p align="center">
  <img src="docs/images/monitor.png" alt="Humanize Monitor" width="680"/>
</p>

## Documentation

- [Usage Guide](docs/usage.md) -- Provider-aware commands, options, and lifecycle
- [Install for Claude Code](docs/install-for-claude.md) -- Existing Claude Code workflow
- [Install for Codex](docs/install-for-codex.md) -- Native Skills, roles, migration, and verification
- [Install for Kimi](docs/install-for-kimi.md) -- Existing Kimi provider workflow
- [Configuration](docs/usage.md#configuration) -- Shared legacy-provider configuration
- [Bitter Lesson Workflow](docs/bitlesson.md) -- Project memory, selector routing, and delta validation

## License

MIT
