# Install Codex Humanizer for Codex

Codex Humanizer is a Codex-only Skill set. It uses native Codex child threads and a deterministic Python state machine. It does not install a Stop hook, enable `codex_hooks`, launch nested model processes, or install Claude/Kimi commands.

## Quick Install

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

The equivalent explicit command is:

```bash
./scripts/install-codex-humanizer.sh
```

## Install Locations

The default remains the historical Codex user Skill root:

```text
${CODEX_HOME:-~/.codex}/skills
```

Installed directories:

```text
codex-humanizer/
codex-humanizer-gen-plan/
codex-humanizer-refine-plan/
codex-humanizer-rlcr/
```

The shared runtime is:

```text
${CODEX_HOME:-~/.codex}/skills/codex-humanizer/scripts/
```

Only these runtime files are installed:

- `native-rlcr.py`;
- `native_rlcr_common.py`;
- `native_rlcr_state.py`;
- `native_rlcr_run.py`;
- `native_rlcr_review.py`;
- `native_rlcr_runtime.py`;
- `codex-humanizer-plan-io.py`.

## Upgrade and Migration

The installer recognizes this fork's previous native installation only when the old `humanize` runtime contains `scripts/native-rlcr.py` and the old Skill contains a native Codex signature. It then removes the four old names:

```text
humanize
humanize-gen-plan
humanize-refine-plan
humanize-rlcr
```

If that signature is absent, similarly named directories are preserved rather than deleted blindly.

The installer also runs the existing targeted cleanup for stale Humanize-managed Stop-hook commands. Unrelated Codex hooks are preserved. No new hook is installed.

Restart Codex after installation so Skill discovery drops the old names and loads the new ones.

## Custom Locations

```bash
./scripts/install-skills-codex.sh \
  --codex-skills-dir /custom/codex/skills \
  --codex-config-dir /custom/codex
```

`--skills-dir` remains an alias for `--codex-skills-dir`.

## Verify

```bash
skills_root="${CODEX_HOME:-$HOME/.codex}/skills"

for skill in \
  codex-humanizer \
  codex-humanizer-gen-plan \
  codex-humanizer-refine-plan \
  codex-humanizer-rlcr
do
  test -f "$skills_root/$skill/SKILL.md"
done

python3 "$skills_root/codex-humanizer/scripts/native-rlcr.py" --help
python3 "$skills_root/codex-humanizer/scripts/codex-humanizer-plan-io.py" --help

rg 'fork_turns: "none"|fork_context: false' \
  "$skills_root/codex-humanizer"*/SKILL.md
```

The installed Skill files must contain an absolute runtime path rather than `{{HUMANIZE_RUNTIME_ROOT}}`.

## Model and Reasoning Overrides

Model and reasoning selections belong to the live invocation. They are not CLI flags and are not persisted.

- Omit both fields for inheritance.
- Pass both as actual `spawn_agent` fields for an explicit override.
- Use a non-full-history fork.
- Stop visibly if the active schema cannot represent the requested override.

## No Hook Requirement

Normal operation does not depend on `$CODEX_HOME/hooks.json`. Phase transitions occur only when the live root thread explicitly runs the deterministic runtime commands named by `$codex-humanizer-rlcr`.
