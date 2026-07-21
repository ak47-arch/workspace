# Agent Instructions

## Knowledge Base

`docs/knowledge/` contains curated knowledge entries from past sessions —
design decisions, architectural rationale, issues, and other learnings. The
knowledge base is manually curated so it won't have everything.

If you encounter a complex bug, an unfamiliar feature, or need to understand
why something was done, check `docs/knowledge/index.md` — there may be an
entry on that topic.

Each entry links to a `session.jsonl` file. If the summary isn't enough, run:
```
node docs/knowledge/bin/extract-context docs/knowledge/<topic>/<entry>/session.jsonl
```
to reconstruct the exact context window from that session.

<!-- OPENWIKI:START -->

## OpenWiki

This repository uses OpenWiki for recurring code documentation. Start with `openwiki/quickstart.md`, then follow its links to architecture, workflows, domain concepts, operations, integrations, testing guidance, and source maps.

The scheduled OpenWiki GitHub Actions workflow refreshes the repository wiki. Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate.

<!-- OPENWIKI:END -->
