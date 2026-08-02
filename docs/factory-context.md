# Factory Context

This is where everything is. If you need anything just follow the trail.

## Software Factory

This workspace is developed and maintained under a **software factory** paradigm.
Four components, one rule: the user only interacts with the product/architecture
layer — everything else is automation.

**context_engine** — Infrastructure spine. Every other component reads/writes it.
Progressive disclosure keeps agents lean: context loads on demand, never pre-loaded.
Agents follow the chain downward and stop when they have enough. The knowledge base
(`docs/knowledge/` — curated design decisions) is the last stop — consulted only
when code, docs, and vision don't answer the question.

**product/architecture** — UX layer. The only surface the user interacts with.
Produces one artifact per task: a single plan document that accumulates Product
Design, System Architecture, and Program Design sections based on task size.
Invoked via the `product-layer` skill.

**project_management** — Prioritisation and lifecycle tracking. Task dashboard
(remote), task files (`docs/tasks/<slug>.md`), lifecycle state machine
(`in-prd` → `prd-ready` → `in-progress` → `in-review` → `complete`).
Tooling: `bin/transition-task.sh`.

**assembly_line** — CI/CD, agents, sandboxes, testing. Built YAGNI — least
developed component.

## Progressive Disclosure

The agent discovers context on demand. It never loads everything at once.

```
AGENTS.md
  "Code is truth. For full inventory, see factory-context.md.
   Knowledge base is the last resort."
    │
    ▼
factory-context.md (this file)
  Factory model, project inventory, vision doc pointers, link index.
    │
    ▼
Discovery layer
  openwiki/           Per-project code docs (what/how)
  docs/vision/        Stakeholder vision, end goals (why a project exists)
  docs/prd-queue/     Forward-looking specs for active tasks
  .agents/skills/     Operational playbooks
    │
    ▼ (last resort)
Knowledge base
  docs/knowledge/index.md  →  decisions  →  session.jsonl (full context)
```

Initial context footprint: ~2,500 tokens (system prompt + AGENTS.md + skills +
subagent tool description).

The knowledge base is the deepest and most expensive layer. It's deliberately
the last stop — agents only drill into it when code and OpenWiki can't explain
why something was built a certain way. Each entry is a structured decision
record with a link to the raw session trace for full reconstruction.

## Projects

Each first-party project has its own `openwiki/` for project-specific documentation.

| Project | Status | Docs |
|---------|--------|------|
| `llm/` | Inference server. ✅ Running | [openwiki](openwiki/projects/llm-server-client.md) |
| `survival-infrastructure/` | Personal intelligence pipeline. 🟡 Broken preflight | [openwiki](openwiki/projects/survival-infrastructure.md) |
| `feed_analyser/` | Capture instrument: thin Chrome extension + minimal local server. Legacy version archived. | [archive/openwiki](https://github.com/ak47-arch/feed_analyser/tree/main/archive/openwiki) (legacy) |
| `headroom-pi/` | Compression proxy for pi. 🟡 Needs eval | project's own `openwiki/` |
| `workspace-portability/` | Backup/restore/bootstrap. ✅ Phase 1 done | project's own `openwiki/` |
| `resume/` | Resume editor. Deferred — not actively developed | project's own `openwiki/` |
| `emotional_architecture/` | Personal operating manual. Static | — |
| `timesheetViewer/` | Timesheet validation. Deferred | — |

## Vision / Design Intent

When you need to understand **why** something was built or why it works a
particular way, consult each project's vision or design doc.

**Convention**: [docs/vision-convention.md](vision-convention.md)

| Project | Vision Doc | Status |
|---------|-----------|--------|
| `survival-infrastructure/` | [`docs/technical/VISION.md`](../survival-infrastructure/docs/technical/VISION.md) — stakeholder vision | ✅ Written |
| `survival-infrastructure/` | [`docs/technical/TECHNICAL_VISION.md`](../survival-infrastructure/docs/technical/TECHNICAL_VISION.md) — technical roadmap | ✅ Written |
| `feed_analyser/capture/` | [`docs/vision/VISION.md`](../feed_analyser/capture/docs/vision/VISION.md) — capture instrument vision | ✅ Written |
| `llm/` | [`docs/vision/VISION.md`](../llm/docs/vision/VISION.md) — inference server & client vision | ✅ Written |
| `headroom-pi/` | [`docs/vision/VISION.md`](../headroom-pi/docs/vision/VISION.md) — compression proxy vision | ✅ Written |
| `workspace-portability/` | [`docs/vision/VISION.md`](../workspace-portability/docs/vision/VISION.md) — portability system vision | ✅ Written |
| `resume/` | — | ❌ Missing (deferred) |

These give you the bigger picture of what each project is about and where it's
headed. Read the relevant one when you need context about purpose or direction
before making changes.

## Pointers

- [Tasks → docs/tasks.txt](tasks.txt)
- [Known Issues → docs/KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [Knowledge Base → docs/knowledge/index.md](knowledge/index.md)
- [Architecture → openwiki/architecture/overview.md](../openwiki/architecture/overview.md)
- [Operations → openwiki/operations/infrastructure.md](../openwiki/operations/infrastructure.md)
- [Agent Config → openwiki/reference/agent-config.md](../openwiki/reference/agent-config.md)
- [Quickstart → openwiki/quickstart.md](../openwiki/quickstart.md)
