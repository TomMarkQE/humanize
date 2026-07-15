---
name: humanize-consult
description: Obtain a bounded independent repository analysis in a visible Codex native researcher subagent thread.
---

# Humanize Native Consultation

Use this skill for a second opinion, architecture analysis, focused investigation, or review question that does not need the full RLCR loop.

Spawn exactly one `humanize_researcher` native subagent. Give it the user's question, repository scope, relevant constraints, and the required evidence. Wait for the child result and return a concise synthesis with paths, symbols, commands, and uncertainty where appropriate.

Do not run `ask-codex.sh`, `codex exec`, `codex review`, or another model CLI. The consultation must remain a child thread of the current Codex task.

The researcher is read-only and may not spawn descendants. If it is unavailable, cancelled, or blocked by permissions, report that state directly instead of falling back to a hidden process.
