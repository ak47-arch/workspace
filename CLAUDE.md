# Agent Instructions

This workspace is developed and maintained under a **software factory** paradigm. See `docs/factory-context.md` for the full model.

Code is the source of truth. When you need deeper context, consult OpenWiki
documentation. The knowledge base is the last resort — only contains manually
curated entries from past sessions about design decisions and issues.

For a full inventory of projects, tasks, issues, and documentation, see
`docs/factory-context.md`.

<!-- OPENWIKI:START -->

## OpenWiki

This repository uses OpenWiki for recurring code documentation. Start with `openwiki/quickstart.md`, then follow its links to architecture, workflows, domain concepts, operations, integrations, testing guidance, and source maps.

The scheduled OpenWiki GitHub Actions workflow refreshes the repository wiki. Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate.

<!-- OPENWIKI:END -->

## Knowledge Base (Last Resort)

`docs/knowledge/` contains curated knowledge entries from past sessions —
design decisions, architectural rationale, issues, and other learnings that
weren't captured in code or OpenWiki docs. The knowledge base is manually
curated so it won't have everything.

If you've exhausted code and OpenWiki and still can't trace why something was
done, check `docs/knowledge/index.md` — there may be an entry on that topic.

Each entry links to a `session.jsonl` file. If the summary isn't enough, run:
```
node docs/knowledge/bin/extract-context docs/knowledge/<topic>/<entry>/session.jsonl
```
to reconstruct the exact context window from that session.
