# Install Humanize for Codex

The Codex-native Humanize path uses Skills and custom agent roles. The current Codex task coordinates the workflow, while delegated implementation, bounded research, implementation review, and final code review appear as visible native child threads.

The Codex path does not install a Humanize Stop hook and does not start `codex exec`, `codex review`, or another model CLI from shell.

## Capability requirements

Use a current Codex build with all of these capabilities:

- Skills loaded from user or repository Skill locations;
- native subagent delegation in Codex App, CLI, or IDE;
- user-scoped or repository-scoped custom agents;
- support for the `spawn_agent` fields used by the active multi-agent version;
- Python 3.8 or newer and Git for deterministic runtime checks.

Humanize uses capability-based support rather than claiming an unpublished numeric minimum Codex version. When reporting a compatibility problem, include `codex --version`, the active client, whether a direct native child can be created in the same task, and the visible `spawn_agent` schema when available.

Subagents inherit the parent task's live working directory, sandbox, and approval choices. Select a parent permission mode that can perform the requested implementation before starting RLCR. Custom role files define bounded behavior and prompt contracts; they do not provide a separately guaranteed permission sandbox after the live parent profile is applied. The worker is the only role authorized by Humanize to change repository files. Researcher and reviewer roles are mandatory no-write contracts, and the coordinator verifies branch, HEAD, index, tracked status, and untracked non-Humanize files before integrating their results.

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

The Codex runtime bundle contains only deterministic state, validation, configuration-loading, and template assets needed by the native Skills. It intentionally omits the legacy Stop-hook reviewer runtime, `ask-codex.sh`, `setup-rlcr-loop.sh`, and the model-backed BitLesson selector.

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

`--target both` installs the existing Kimi provider bundle and the Codex-native bundle into separate locations. The installer rejects a shared Skill directory because provider-specific orchestration assets differ. A Kimi-owned selector shim is preserved during Codex migration.

## Verify the installation

```bash
test -f ~/.agents/skills/humanize-rlcr/SKILL.md
test -f ~/.agents/skills/humanize-gen-plan/SKILL.md
test -f ~/.agents/skills/humanize-refine-plan/SKILL.md
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

No installed role may pin a model, model reasoning effort, or sandbox mode:

```bash
! grep -RE '^[[:space:]]*(model|model_reasoning_effort|sandbox_mode)[[:space:]]*=' \
  ~/.codex/agents/humanize-*.toml
```

This is intentional: the live parent task supplies effective permissions. Verify that researcher and reviewer files contain explicit `Never edit files` instructions and that the installed RLCR Skill contains its no-write baseline checks.

A successful install does not require or create `~/.codex/hooks.json`. When that file already exists, unrelated hooks remain unchanged.

## Runtime model and reasoning selection

Humanize does not store a native child model or reasoning-effort default. Selection belongs to the current invocation.

Inheritance example:

```text
Use $humanize-rlcr to implement docs/plan.md. Let every child inherit the current parent model and reasoning effort.
```

In this case the coordinator must omit `model` and `reasoning_effort` from each `spawn_agent` call.

Explicit override example:

```text
Use $humanize-rlcr to implement docs/plan.md.
For research and review children, use <available-model> with <effort>.
Pass the selection as actual spawn_agent model and reasoning_effort fields.
Use a non-full-history fork.
```

For an explicit override, the selected values must appear in the real tool call. Mentioning a model only inside the child prompt is not sufficient. Because Humanize also selects a custom `agent_type`, use a compatible non-full-history mode:

- multi-agent V2: `fork_turns: "none"` or a deliberately bounded positive turn count;
- multi-agent V1: `fork_context: false`.

Do not combine a full-history fork with `agent_type`, `model`, or `reasoning_effort`. If the requested model or effort is unavailable or rejected, treat that as `agent_unavailable`; do not silently inherit, substitute another model, or start a hidden CLI fallback.

## Start a native RLCR run

In a Codex task opened on the target repository, ask:

```text
Use $humanize-rlcr to implement docs/plan.md.
```

Supported workflow options:

```text
--max N                 Maximum rounds; default 42
--max-rounds N          Alias for --max
--base-ref REF          Fixed diff and review base
--base-branch REF       Alias for --base-ref
--track-plan-file       Fail if the source plan changes
--review-only           Start with independent code review
--skip-impl             Migration alias for --review-only
```

The legacy `--codex-model`, `--codex-timeout`, `--agent-teams`, `--claude-answer-codex`, and `--yolo` flags are not part of native RLCR state. Express model/effort choices in the invocation so the coordinator can pass them directly to the child tool call. Sandbox and approval behavior comes from the live Codex task. Claude Agent Teams remains Claude-only.

## What users see

The root Codex thread remains the coordinator. It creates child threads for:

- `humanize_worker`: implementation and fix commits under inherited live permissions;
- `humanize_implementation_reviewer`: behaviorally no-write independent plan and acceptance review;
- `humanize_code_reviewer`: behaviorally no-write independent branch-diff review;
- `humanize_researcher`: behaviorally no-write bounded investigation.

Only the root delegates. The worker is the only repository writer. A no-write child cannot overlap with the worker or another writer because the coordinator must attribute any repository-state change. Independent no-write research may overlap only when questions and evidence scopes are independent. The root must perform useful non-overlapping no-write work before joining and must collect, baseline-check, verify, and integrate every required child result before a dependent edit, state transition, plan write, or final report.

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

## Real native forward test

Repository tests validate source and installed Skill contracts, agent definitions, installer migration, deterministic runtime transitions, no-write baseline requirements, and failure behavior without consuming a model invocation. They do not prove that a particular Codex client/account currently exposes a requested model override or that a real child obeyed its behavioral contract.

After installation, forward-test in an isolated temporary repository and a fresh Codex root task:

1. **Explicit override case**
   - choose an available model that differs from the current parent default and a supported reasoning effort;
   - invoke `$humanize-consult`, `$humanize-gen-plan`, or `$humanize-rlcr` with an explicit instruction to use those values as actual fields;
   - open the child activity/metadata and confirm the emitted `spawn_agent` call or effective child metadata contains the requested `model` and `reasoning_effort` and uses `fork_turns: "none"`/bounded turns or `fork_context: false`.
2. **Inheritance case**
   - run again without an override;
   - confirm the tool call omits `model` and `reasoning_effort` and the child inherits the live parent selection.
3. **Parent progress and join case**
   - confirm the root performs useful non-overlapping work after spawning;
   - confirm it does not finalize, write the final plan/QA, or advance RLCR state before collecting and integrating the child evidence.
4. **No-write verification case**
   - for researcher and reviewer children, confirm the coordinator records branch/HEAD/index/tracked/untracked state before spawn and verifies it before integration;
   - confirm no no-write child overlaps with a worker or another writer;
   - if a controlled negative test is available, confirm an unexpected repository change prevents integration and runtime advancement.
5. **Compatibility case**
   - confirm generated plan/refinement schemas, validators, atomic writes, fixed review base, reviewer markers, and deterministic state behavior remain unchanged.

Record the client, Codex version, parent model/effort, requested child values, observed fork mode, child metadata, before/after repository-state evidence, and final output paths. If the client hides model overrides or metadata, report that capability limitation rather than claiming the override was verified.

## Completion and failure states

Humanize reports one of these outcomes:

- `complete`: an independent code reviewer returned `pass` with no unresolved `[P0-9]` finding and its no-write baseline matched;
- `blocked`: a required native child was unavailable, permissions prevented required work, review evidence was inaccessible, or the mainline repeatedly stalled;
- `failed`: validation failed, maximum rounds were exhausted, a child could not finish required work, or a no-write child changed repository state;
- `cancelled`: the user stopped the workflow;
- `active`: another implementation or review action remains.

There is no hidden nested-CLI fallback. Humanize records `agent_unavailable`, `permission_denied`, `cancelled`, `interrupted`, `agent_failed`, or `validation_failed` as applicable. Malformed reviewer contracts, branch changes, rewritten checkpoint history, corrupt state, plan tampering, dirty worker checkpoints, no-write child state changes, and internal runtime errors return non-zero exits and do not silently advance state. Native state transitions are serialized with per-loop file locks.

## Migration from the legacy Codex install

Running the Codex-native installer performs an idempotent migration:

1. It removes only Humanize-managed Stop-hook commands from `<CODEX_HOME>/hooks.json` and preserves unrelated hook events and commands.
2. It removes duplicate Humanize Skill copies from the former `<CODEX_HOME>/skills` location when the current Skill directory is different.
3. It removes a legacy `bitlesson-selector` shim only when that shim points at the former Codex Skill runtime. A Kimi-owned shim with the same filename is preserved.
4. It installs native Skills and custom roles and writes an ownership manifest.

The Codex-native path does not retain a shell reviewer fallback. Claude Code and Kimi keep their existing workflows and shared assets. A project that deliberately requires the former hidden Codex CLI behavior must use a pre-native Codex installation; it cannot be enabled accidentally by the native installer.

The compatibility entrypoint `scripts/install-codex-hooks.sh` now removes legacy managed hooks instead of installing them.

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

**The custom role is unavailable**

Confirm the TOML file exists under `~/.codex/agents/`, contains `name`, `description`, and `developer_instructions`, and restart Codex. Humanize stops with `agent_unavailable`; it does not start another Codex process.

**An explicit model or effort is rejected**

Use a model and effort exposed by the current Codex client for native subagents. Keep the requested values in the real `spawn_agent` fields and use a non-full-history fork. Do not solve the error by adding a Humanize model default.

**A worker cannot write or run a command**

Subagents inherit the current parent permission mode. Review the blocked operation and restart or continue with an appropriate parent permission choice. Do not broaden permissions merely to bypass a nonessential step.

**A researcher or reviewer changed repository state**

Do not integrate its result and do not automatically reset the tree. Compare the recorded baseline with the current branch, HEAD, index, tracked status, and untracked non-Humanize files; report the exact delta and persist `agent_failed` or `permission_denied`. Because effective permissions inherit from the parent, Humanize relies on the child no-write contract plus this observable verification rather than claiming hard role isolation.

**The runtime rejects initialization or a checkpoint**

Start from a clean non-Humanize tree. An untracked source plan is allowed and is copied into an immutable loop snapshot. Common checkpoint causes are uncommitted files, no new descendant commit, rewritten history, branch drift, a changed plan snapshot, or an incomplete round summary.

**The test runner reports an internal failure**

Run `python3 tests/run-all-tests.py --jobs 1` to get deterministic per-suite output. Missing suites, launch errors, and non-zero suite exits all make the aggregate runner fail.

## Supported validation environment

The complete repository suite runs in GitHub Actions on Ubuntu with Bash, zsh, jq, Python 3, and Git. The aggregate runner is Python-based and is separately exercised on macOS through system Bash so Bash 3.2 does not encounter associative arrays or `wait -n`. This does not claim that every legacy provider integration test is supported on macOS; the full declared suite environment is Ubuntu CI.

Run the complete suite with:

```bash
./tests/run-all-tests.sh
```

The runner fails on missing suites, launch exceptions, timeouts, non-zero exits, or reported failed assertions. For a deterministic single-threaded diagnosis, use `./tests/run-all-tests.sh --jobs 1`.
