# Factory Context

This is where everything is. If you need anything just follow the trail.

## Projects

| Project | Status | Docs |
|---------|--------|------|
| `llm/` | Inference server. ✅ Running | [openwiki](openwiki/projects/llm-server-client.md) |
| `survival-infrastructure/` | Pipeline app. 🟡 Broken preflight | [openwiki](openwiki/projects/survival-infrastructure.md) |
| `feed_analyser/` | Social media analysis. ✅ Running | [openwiki](openwiki/projects/feed-analyser.md) |
| ~~`mission-control/`~~ | ~~Deprecated — removed from workspace. See `docs/tasks.txt`~~ | ~~—~~ |
| `headroom-pi/` | Compression proxy. 🟡 Needs eval | project's own `openwiki/` |
| `workspace-portability/` | Backup/restore. ✅ Phase 1 done | project's own `openwiki/` |
| `resume/` | Resume editor. 🟡 Needs assessment | project's own `openwiki/` |
| `emotional_architecture/` | Personal operating manual. Static | — |
| `timesheetViewer/` | Timesheet validation. Deferred | — |

Each first-party project has its own `openwiki/` for project-specific documentation.

### Vision / Design Intent

When you need to understand **why** something was built or why it works a particular way, consult each project's vision or design doc:

| Project | Vision / Design Doc |
|---------|--------------------|
| `survival-infrastructure/` | [`docs/technical/VISION.md`](../survival-infrastructure/docs/technical/VISION.md) — stakeholder vision, three-layer model, end goal |
| `feed_analyser/` | [`vision.md`](../feed_analyser/vision.md) — problem statement, core pillars, phased direction |
| ~~`mission-control/`~~ | ~~Deprecated — removed from workspace. See `docs/tasks.txt`~~ |

These give you the bigger picture of what each project is about and where it's headed. Read the relevant one when you need context about purpose or direction before making changes.

## Tasks → [docs/tasks.txt](tasks.txt)
## Known Issues → [docs/KNOWN_ISSUES.md](KNOWN_ISSUES.md)
## Knowledge Base → [docs/knowledge/index.md](knowledge/index.md)
## Architecture → [openwiki/architecture/overview.md](../openwiki/architecture/overview.md)
## Operations → [openwiki/operations/infrastructure.md](../openwiki/operations/infrastructure.md)
## Agent Config → [openwiki/reference/agent-config.md](../openwiki/reference/agent-config.md)
## Quickstart → [openwiki/quickstart.md](../openwiki/quickstart.md)
