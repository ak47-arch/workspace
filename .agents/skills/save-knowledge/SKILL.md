---
name: save-knowledge
description: Capture a structured decision record from the session. Use when preserving design intent or when a significant decision emerges that should be recorded.
---

# Save Knowledge

## Summary

Read the current session, infer a title for the decision, append it as a new structured entry under `docs/knowledge/sessions/<uuid>/decisions/`, and add a link to `docs/knowledge/index.md`. Multiple decisions from the same session accumulate in the same session directory — each independently addressable in the index.

## Finding the current session

Run this to find the session file:
```bash
ls -t ~/.pi/agent/sessions/--*--/*.jsonl 2>/dev/null | head -1
```
This picks the most recently modified `.jsonl` across all session directories — it's the one being written to right now. Verify by reading the first line (the session header) and confirming it has a `"type":"session"` field.

## Re-running on the same session

Multiple saves from the same session add new decision files to the same session directory. The session directory is keyed by UUID, so subsequent saves always find it. Each decision gets its own sequence number — no overwrites.

## Workflow

1. **Find the current session file** using the command above. Read the first line to get the session UUID.

2. **Create or reuse the session directory**:
   ```
   docs/knowledge/sessions/<uuid>/
   ```
   Create it if it doesn't exist. Then **always copy** the session file into it as `session.jsonl`, overwriting any previous copy. The session file grows as the conversation progresses — each save gets the freshest snapshot, which is a strict superset of any earlier one.

   **Then sanitize the copy**: session traces capture tool output (e.g. `cat ~/.config/gh/hosts.yml`, env vars) that can embed live credentials. Committing them trips GitHub Push Protection (GH013) and blocks the save. Run:
   ```bash
   bash bin/sanitize-session.sh docs/knowledge/sessions/<uuid>/session.jsonl
   ```
   This redacts `sk-or-v1-*`, `gho_*`, `ghp_*`, `github_pat_*`, `xox*-*`, `AKIA*` values in place (prefixes kept as `…REDACTED`). If it exits 3 (secrets still present), inspect the file and redact manually before committing.

3. **Read the session entries** — the file is JSONL. Walk the tree from leaf to root via `parentId` to get the active path. Skip entries that are excluded by compaction (a compaction entry with `firstKeptEntryId` replaces everything before that point).

4. **Infer a title** from the conversation. The title should be short and descriptive (e.g. "Payment Flow Architecture Decision"). Also derive a slug from the title for the filename.

5. **Determine the next sequence number** — list files in `docs/knowledge/sessions/<uuid>/decisions/`. If the directory doesn't exist yet, start at `01`. Otherwise, find the highest existing numeric prefix and increment by one.

6. **Determine the task slug** — if the session is associated with a task (i.e., the agent is working on a task from `docs/tasks.txt`), look up the task slug from the task file or from the session context. The slug is the `<slug>` portion of the task file path. Include it in the `Task:` field.

7. **Determine the project slug** — derive the project slug from the task's `**Project**:` field (if a task is associated) or from the session context (which project this session relates to). Use the same hyphenated convention as task files (e.g. `survival-infrastructure`, `software-factory`, `workspace-portability`). Include it in the `Project:` field.

8. **Capture the decision** — write a new file at:
   ```
   docs/knowledge/sessions/<uuid>/decisions/<sequence>-<slug>.md
   ```
   Use the structured format below. Every field matters. The **revision triggers** field is especially important — it tells a future agent when to stop trusting this entry.

9. **Append to `docs/knowledge/index.md`** — add a project-grouped entry. The index is organized by project so entries are discoverable by project context. Add:
   ```markdown
   ### <project-slug>
   - [<title>](sessions/<uuid>/decisions/<sequence>-<slug>.md)
   ```
   If the project section already exists, just add the line under it. Create `index.md` with a `# Knowledge Base` heading if it doesn't exist.

## Structured format

```markdown
## Decision: <title>

**Status**: proposed | accepted | deprecated | superseded
**Date**: <yyyy-mm-dd HH:MM>
**Task**: <slug>
**Project**: <slug>
**Session**: sessions/<uuid>/session.jsonl

### Context

What was happening in the workspace that framed this decision.

### Problem

The specific tension or requirement being addressed.

### Alternatives

What else was considered and why each was rejected or deferred.

### Decision

What was chosen.

### Rationale

Why this path, acknowledging trade-offs.

### Consequences

What changes — things that become easier, harder, or deprecated.

### Revision triggers

Conditions that would make this decision worth re-examining.
```