---
name: save-knowledge
description: Save a knowledge entry from the current session into the knowledge base. Use when the user wants to preserve design decisions, architectural rationale, issues, or other organisation-worthy knowledge.
---

# Save Knowledge

## Summary

Read the current session, infer a title and topic from the conversation, summarise the key decisions/issues/learnings into a freeform markdown file, copy the session file alongside it, and append a link to `docs/knowledge/index.md`.

## Finding the current session

Run this to find the session file:
```bash
ls -t ~/.pi/agent/sessions/--*--/*.jsonl 2>/dev/null | head -1
```
This picks the most recently modified `.jsonl` across all session directories — it's the one being written to right now. Verify by reading the first line (the session header) and confirming it has a `"type":"session"` field.

## Re-running on the same session

If the skill is run multiple times in the same session, the last run wins. Check if this session UUID (`"id":"<uuid>"` from the first line) already exists in any `session.jsonl` under `docs/knowledge/`. If found, **overwrite** that entry's `summary.md` and `session.jsonl` instead of creating a new one. The index.md link stays the same.

## Workflow

1. **Find the current session file** using the command above. Read the first line to get the session UUID.

2. **Check for a previous save** — search all `session.jsonl` files under `docs/knowledge/` for the same UUID. If found, reuse that entry's directory path for the rest of the workflow (overwrite mode).

3. **Read the session entries** — the file is JSONL. Walk the tree from leaf to root via `parentId` to get the active path. Skip entries that are excluded by compaction (a compaction entry with `firstKeptEntryId` replaces everything before that point).

4. **Infer a title and topic** from the conversation. The title should be short and descriptive (e.g. "Payment Flow Architecture Decision"). The topic is a directory name like `architecture`, `payments`, `infrastructure` — pick something that groups related entries.

5. **Summarise** — write a plain markdown summary covering what was decided, why, alternatives considered, and any caveats or open questions. Start with the current date on its own line. Then freeform prose. No template, no frontmatter. Focus on what would be valuable months from now.

6. **Create the entry directory** (or reuse the existing one if overwriting):
   ```
   docs/knowledge/<topic>/<date>-<slug>/
   ```
   Use today's date and a slug derived from the title. If overwriting, reuse the existing path from step 2.

7. **Write `summary.md`** into that directory.

8. **Copy the session file** into that directory as `session.jsonl`.

9. **Append to `docs/knowledge/index.md`** — add one line (skip if overwriting, since the link already exists):
   ```markdown
   - [<title>](<topic>/<date>-<slug>/summary.md)
   ```
   Create `index.md` with a `# Knowledge Base` heading if it doesn't exist.