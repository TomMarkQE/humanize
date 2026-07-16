---
name: humanize-consult
description: Obtain a bounded independent repository analysis in a visible Codex native researcher child thread.
---

# Humanize Native Consultation

Use this skill for a second opinion, architecture analysis, focused investigation, or review question that does not need the full RLCR loop.

Spawn exactly one `humanize_researcher` child with a self-contained prompt containing the question, repository scope, relevant constraints, authoritative inputs, excluded work, and required evidence format. The child is read-only and may not spawn descendants.

Apply the invoking request's runtime selection exactly:

- inheritance case: omit `model` and `reasoning_effort`;
- explicit override case: pass `model` and `reasoning_effort` as actual `spawn_agent` fields;
- V2 explicit override: set `fork_turns: "none"` or a deliberate bounded positive count;
- V1 explicit override: set `fork_context: false`;
- never use a full-history fork with `agent_type` or model/effort overrides.

After spawning, continue useful non-overlapping local work such as identifying the decision the answer must support and preparing an evidence checklist. Do not duplicate the child's investigation. Collect the result only when integration is required, verify its key repository citations, and synthesize the answer. Do not finalize before integrating the child evidence.

Do not run `ask-codex.sh`, `codex exec`, `codex review`, or another model CLI. If the child is unavailable, cancelled, permission-blocked, or the explicit override is unsupported, report that state directly instead of falling back to a hidden process.
