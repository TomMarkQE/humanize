---
name: humanize-consult
description: Obtain a bounded independent repository analysis in a visible Codex native researcher child thread.
---

# Humanize Native Consultation

Use this skill for a second opinion, architecture analysis, focused investigation, or review question that does not need the full RLCR loop.

Spawn exactly one `humanize_researcher` child with a self-contained prompt containing the question, repository scope, relevant constraints, authoritative inputs, excluded work, and required evidence format. The child is behaviorally no-write and may not spawn descendants. Its effective sandbox and approval policy inherit from the live parent task, so the coordinator must verify the no-write contract rather than assume a separate hard sandbox.

Before spawning, record:

- the current branch and exact `HEAD` commit;
- staged and unstaged tracked-file status;
- untracked non-Humanize files;
- any existing dirty state that the parent intentionally preserves.

The parent must not change repository state while the researcher runs. This makes the before/after comparison attributable to the child.

Apply the invoking request's runtime selection exactly:

- inheritance case: omit `model` and `reasoning_effort`;
- explicit override case: pass `model` and `reasoning_effort` as actual `spawn_agent` fields;
- V2 explicit override: set `fork_turns: "none"` or a deliberate bounded positive count;
- V1 explicit override: set `fork_context: false`;
- never use a full-history fork with `agent_type` or model/effort overrides.

After spawning, continue useful non-overlapping local work such as identifying the decision the answer must support and preparing an evidence checklist. Do not duplicate the child's investigation or modify repository files. Collect the result only when integration is required.

Before integrating the result, confirm the branch, `HEAD`, index, tracked-file status, and untracked non-Humanize set match the recorded baseline. A mismatch is a child role violation: do not use the result, identify the exact change, restore nothing automatically, and report `agent_failed` or `permission_denied` as appropriate. When the tree is unchanged, verify key repository citations and synthesize the answer. Do not finalize before integrating the child evidence.

Do not run `ask-codex.sh`, `codex exec`, `codex review`, or another model CLI. If the child is unavailable, cancelled, permission-blocked, or the explicit override is unsupported, report that state directly instead of falling back to a hidden process.
