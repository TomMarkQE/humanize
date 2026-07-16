# Install Humanize Skills for Codex

Humanize's Codex path uses provider-specific skills and native Codex child threads. The root Codex thread performs orchestration; the installed Python runtime performs deterministic Git, state-transition, validation, and atomic-write checks only.

The Codex install does not register a Humanize Stop hook, does not enable `codex_hooks`, and does not launch nested model processes. During upgrade it removes only legacy Humanize-managed Stop-hook entries from `hooks.json` and preserves unrelated hooks.

## Quick install

From anywhere:

```bash
tmp_dir="$(mktemp -d)" && \
  git clone --depth 1 https://github.com/PolyArch/humanize.git "$tmp_dir/humanize" && \
  "$tmp_dir/humanize/scripts/install-skills-codex.sh"
```

From a Humanize checkout:

```bash
./scripts/install-skills-codex.sh
```

The unified installer is equivalent:

```bash
./scripts/install-skill.sh --target codex
```

## What is installed

The installer:

- copies `codex-skills/humanize`, `humanize-gen-plan`, `humanize-refine-plan`, and `humanize-rlcr` into `${CODEX_HOME:-~/.codex}/skills`;
- copies the deterministic runtime into `${CODEX_HOME:-~/.codex}/skills/humanize`;
- hydrates absolute runtime paths in installed Skill files;
- strips Claude-only frontmatter from installed Codex copies;
- removes stale Humanize-managed Stop-hook commands from `${CODEX_HOME:-~/.codex}/hooks.json` while preserving unrelated hooks;
- leaves native subagent model and reasoning selection to each invocation;
- preserves the existing BitLesson selector configuration and helper shim.

Source Claude/Kimi skills remain under `skills/` and are not replaced by the Codex-specific Skill content.

## Verify source and installed copies

```bash
codex_skills="${CODEX_HOME:-$HOME/.codex}/skills"

ls -la "$codex_skills"
python3 "$codex_skills/humanize/scripts/native-rlcr.py" --help
rg 'Humanize Native RLCR Coordinator' "$codex_skills/humanize-rlcr/SKILL.md"
rg 'fork_turns: "none"|fork_context: false' \
  "$codex_skills/humanize-gen-plan/SKILL.md" \
  "$codex_skills/humanize-refine-plan/SKILL.md" \
  "$codex_skills/humanize-rlcr/SKILL.md"
```

Expected Skill directories:

- `humanize`
- `humanize-gen-plan`
- `humanize-refine-plan`
- `humanize-rlcr`

The installed `humanize/hooks` directory is intentionally absent on the Codex target.

## Runtime model and reasoning selection

Humanize does not store a native subagent model or reasoning default. In the Codex invocation, state the desired override globally or per role. For example:

```text
Use $humanize-rlcr to execute docs/plan.md.
Use the current runtime selection for the worker.
For the researcher and reviewers, use the explicit model and reasoning effort I provide here.
Pass each explicit choice as actual spawn_agent model and reasoning_effort fields.
```

The Skill requires:

- omitted overrides to inherit the current root selection;
- explicit overrides to be present in the actual `spawn_agent` payload;
- V2 spawns to use `fork_turns: "none"`;
- V1 spawns to use `fork_context: false`;
- a capability error when requested fields are unavailable, instead of simulating an override through prompt text.

## Native RLCR artifacts

`$humanize-rlcr` initializes and advances runs with:

```bash
python3 "$codex_skills/humanize/scripts/native-rlcr.py" start --plan docs/plan.md
```

Artifacts remain under `.humanize/rlcr/<timestamp>/` and include:

- `state.md` during implementation and review;
- `plan.md` and `goal-tracker.md`;
- `round-N-contract.md`;
- `round-N-summary.md`;
- `round-N-research.md` when research was delegated;
- `round-N-implementation-review.md`;
- `round-N-code-review.md`;
- `finalize-state.md` during finalization;
- `complete-state.md`, `blocked-state.md`, `failed-state.md`, or `cancelled-state.md` at termination;
- `events.jsonl` for deterministic transition evidence.

The runtime never chooses or invokes a model. The root thread uses native `spawn_agent`, `followup_task`, and wait/collection tools according to the installed Skill.

## Useful options

```bash
# Preview install and legacy-hook migration
./scripts/install-skills-codex.sh --dry-run

# Custom Codex skills/config locations
./scripts/install-skills-codex.sh \
  --codex-skills-dir /custom/codex/skills \
  --codex-config-dir /custom/codex

# Remove only stale Humanize-managed Codex hooks
bash ./scripts/remove-codex-hooks.sh --codex-config-dir "${CODEX_HOME:-$HOME/.codex}"
```

## Install for Codex and Kimi

Provider-specific Skill content requires separate target directories:

```bash
./scripts/install-skill.sh \
  --target both \
  --kimi-skills-dir "$HOME/.config/agents/skills" \
  --codex-skills-dir "${CODEX_HOME:-$HOME/.codex}/skills"
```

## Troubleshooting

If an installed Skill still references the placeholder runtime root, rerun the installer and verify the target directory is writable.

If a previous Humanize Stop hook remains, inspect `${CODEX_HOME:-~/.codex}/hooks.json`, then run `remove-codex-hooks.sh`. The migration intentionally preserves all non-Humanize hook commands.

If an explicit child override does not appear in the available `spawn_agent` schema, the installed Skill must stop blocked. Upgrade or reconfigure Codex so the actual `model` and `reasoning_effort` fields are exposed; do not place those values only in child prompt text.
