# Install Humanize for Codex

Humanize 2.0 uses Codex's native Skills and custom agents. The current Codex task coordinates the workflow, and delegated implementation, research, and review work appears as native child agent threads.

The Codex path does not install a Humanize Stop hook and does not start `codex exec` or `codex review` from a shell.

## Capability requirements

Use a current Codex build with all of these capabilities:

- Skills loaded from the user or repository Skill locations;
- native subagent delegation in Codex App, CLI, or IDE;
- user-scoped or repository-scoped custom agents;
- Python 3.8 or newer and Git available to deterministic runtime checks.

Humanize uses capability-based support rather than claiming an unpublished numeric minimum Codex version. When reporting a compatibility problem, include `codex --version` and whether a direct request to spawn a subagent works in the same client.

Subagents inherit the parent task's live sandbox and approval choices. Select a parent permission mode that can perform the requested implementation before starting the loop. Review and research agents are installed read-only; the worker defaults to workspace-write but remains subject to the parent session's overrides.

## Install from a checkout

```bash
git clone https://github.com/PolyArch/humanize.git
cd humanize
./scripts/install-skills-codex.sh
```

Default destinations:

```text
~/.agents/skills/humanize/
~/.agents/skills/humanize-rlcr/
~/.agents/skills/humanize-consult/
~/.agents/skills/humanize-gen-plan/
~/.agents/skills/humanize-refine-plan/
~/.codex/agents/humanize-worker.toml
~/.codex/agents/humanize-implementation-reviewer.toml
~/.codex/agents/humanize-code-reviewer.toml
~/.codex/agents/humanize-researcher.toml
~/.codex/humanize-native-install.json
```

The installer puts only deterministic scripts in the Codex runtime bundle. It intentionally omits the legacy hook runtime, `ask-codex.sh`, `setup-rlcr-loop.sh`, and the model-backed BitLesson selector.

Restart Codex App, CLI, or the IDE extension after installation so it reloads Skills and custom agents.

## Custom locations

```bash
./scripts/install-skills-codex.sh \
  --codex-skills-dir /path/to/agent-skills \
  --codex-config-dir /path/to/codex-config \
  --codex-agents-dir /path/to/codex-config/agents
```

`--codex-agents-dir` defaults to `<codex-config-dir>/agents`. `--dry-run` reports migration and copy actions without writing.

The unified installer also routes Codex to the native path:

```bash
./scripts/install-skill.sh --target codex
```

`--target both` installs the existing Kimi provider bundle and the Codex-native bundle into separate locations. The installer rejects a shared Skill directory because the provider-specific `humanize` and `humanize-rlcr` assets intentionally differ. The Kimi selector shim is preserved during the Codex migration step.

## Verify the installation

```bash
test -f ~/.agents/skills/humanize-rlcr/SKILL.md
test -f ~/.codex/agents/humanize-worker.toml
test -f ~/.codex/agents/humanize-code-reviewer.toml
python3 ~/.agents/skills/humanize/scripts/native-rlcr.py --help
```

The installed RLCR Skill should name all four native roles and contain an absolute runtime path:

```bash
grep -E 'humanize_(worker|implementation_reviewer|code_reviewer|researcher)' \
  ~/.agents/skills/humanize-rlcr/SKILL.md
grep -q '{{HUMANIZE_RUNTIME_ROOT}}' ~/.agents/skills/humanize-rlcr/SKILL.md \
  && echo 'unexpected unhydrated Skill' >&2
```

A successful install does not require or create `~/.codex/hooks.json`. When that file already exists, unrelated hooks remain unchanged.

## Start a native RLCR run

In a Codex task opened on the target repository, ask:

```text
Use $humanize-rlcr to implement docs/plan.md.
```

Supported workflow options:

```text
--max N                 Maximum rounds; default 42
--base-ref REF          Diff and review base
--track-plan-file       Fail if the source plan changes
--review-only           Start with independent code review
--skip-impl             Migration alias for --review-only
```

The former `--codex-model`, `--codex-timeout`, `--agent-teams`, `--claude-answer-codex`, and `--yolo` options are not part of the native Codex path. Model, effort, sandbox, and approval behavior now come from the current Codex session and custom-agent configuration. Claude Agent Teams remains a Claude-only provider feature.

## What users see

The root Codex thread remains the coordinator. It creates child threads for:

- `humanize_worker`: implementation and fix commits;
- `humanize_implementation_reviewer`: independent plan and acceptance review;
- `humanize_code_reviewer`: independent branch-diff review;
- `humanize_researcher`: bounded read-only investigation.

Only the root thread delegates, so Codex's default subagent depth of one is sufficient. Writing work is sequential to avoid conflicting edits. Read-only research may be parallelized only when questions are independent.

The loop writes deterministic evidence under `.humanize/rlcr/<run>/`:

```text
state.json
plan.md
goal-tracker.md
round-N-summary.md
round-N-implementation-review.md
round-N-code-review.md
events.jsonl
```

These files record state and results; they are not a substitute for native agent threads.

## Completion and failure states

Humanize reports one of these outcomes:

- `complete`: an independent code reviewer returned `pass` with no unresolved `[P0-9]` finding;
- `blocked`: a required native agent was unavailable, permissions prevented required work, review evidence was inaccessible, or the mainline repeatedly stalled;
- `failed`: validation failed, maximum rounds were exhausted, or an agent could not finish required work;
- `cancelled`: the user stopped the workflow;
- `active`: another implementation or review action remains.

There is no hidden nested-CLI fallback. When native agents are unavailable, Humanize records `agent_unavailable` and explains the capability that is missing. Permission failures record `permission_denied` with the blocked operation. Malformed reviewer contracts, branch changes, rewritten checkpoint history, corrupt state, plan tampering, dirty worker checkpoints, and internal runtime errors return non-zero exits and do not silently advance state. Native state transitions are serialized with per-loop file locks.

## Migration from Humanize 1.x Codex installs

Running the 2.0 installer performs an idempotent migration:

1. It removes only Humanize-managed Stop-hook commands from `<CODEX_HOME>/hooks.json` and preserves unrelated hook events and commands.
2. It removes duplicate Humanize Skill copies from the former `<CODEX_HOME>/skills` location when the new Skill directory is different.
3. It removes a legacy `bitlesson-selector` shim only when that shim points at the former Codex Skill runtime. A Kimi-owned shim with the same filename is preserved.
4. It installs the native Skills and custom agents and writes an ownership manifest.

The 2.0 Codex path does not retain a shell reviewer fallback. Claude Code and Kimi retain their existing provider workflows. A project that deliberately requires the former hidden Codex CLI behavior must stay on a pre-2.0 checkout; it cannot be enabled accidentally by the native installer.

The deprecated `scripts/install-codex-hooks.sh` entrypoint now removes legacy managed hooks instead of installing them.

## Upgrade

From an updated checkout, rerun:

```bash
./scripts/install-skills-codex.sh
```

The operation is idempotent. Managed Skills and agents are replaced, stale managed copies are removed, and unrelated user assets are preserved.

## Uninstall

```bash
./scripts/uninstall-skills-codex.sh
```

The uninstaller reads `~/.codex/humanize-native-install.json`, removes only recognized Humanize-managed Skills and agents, removes legacy Humanize hook commands if any remain, and preserves unrelated hooks and custom agents.

Use the same custom directory options passed during install when the manifest is unavailable.

## Troubleshooting

**The Skill is not discovered**

Confirm that it is under `~/.agents/skills/<skill-name>/SKILL.md`, then restart the Codex client. A repository-scoped alternative is `.agents/skills/` in the project.

**The custom agent name is unavailable**

Confirm the TOML file exists under `~/.codex/agents/`, contains `name`, `description`, and `developer_instructions`, and restart Codex. Humanize stops with `agent_unavailable`; it does not start another Codex process.

**A worker cannot write or run a command**

Subagents inherit the current parent permission mode. Review the blocked operation and restart or continue with an appropriate parent permission choice. Do not broaden permissions merely to bypass a nonessential step.

**The runtime rejects initialization or a checkpoint**

Start from a clean non-Humanize tree. An untracked source plan is allowed and is copied into an immutable loop snapshot. Common checkpoint causes are uncommitted files, no new descendant commit, rewritten history, branch drift, a changed plan snapshot, or an incomplete round summary.

**The test runner reports an internal failure**

Run `python3 tests/run-all-tests.py --jobs 1` to get deterministic per-suite output. Missing suites, launch errors, and non-zero suite exits all make the aggregate runner fail.

## Supported validation environment

The complete repository suite runs in GitHub Actions on Ubuntu with Bash, zsh, jq, Python 3, and Git. The aggregate runner itself is Python-based and is separately exercised on macOS 14 through the system `/bin/bash`, so Bash 3.2 does not encounter associative arrays or `wait -n`. This does not claim that every legacy provider integration test is supported on macOS; the full declared suite environment is Ubuntu CI.

Run the complete suite with:

```bash
./tests/run-all-tests.sh
```

The runner fails on missing suites, launch exceptions, timeouts, non-zero exits, or reported failed assertions. For a deterministic single-threaded diagnosis, use `./tests/run-all-tests.sh --jobs 1`.
