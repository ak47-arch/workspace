## Decision: Survival Infrastructure as Core Product — Two-Agent Architecture

**Status**: accepted
**Date**: 2026-07-29
**Session**: sessions/019faf18-7a30-7afe-87ba-3070f248c536/session.jsonl

### Context

The workspace contains 8+ projects (survival-infrastructure, feed_analyser, llm, resume, mission-control, workspace-portability, headroom-pi, software_factory) and a tasks file (`docs/tasks.txt`) that has become the user's primary interface for driving work. Three PRDs exist in `docs/prd-queue/` but none are being implemented. The user expressed frustration that projects are not moving fast enough despite having plenty of work defined.

A deeper investigation revealed that the user's vision had been fragmented across projects without a clear articulation of how they relate. The user clarified: **survival-infrastructure is the product.** Everything else is enabling infrastructure.

### Problem

The workspace had no explicit, shared understanding of:
1. Which project is the actual product vs. supporting infrastructure
2. How the product architecture works at the conceptual level (data sources, agents, decision loop)
3. What the next build priorities should be — everything felt equally important
4. How the tasks file relates to the product vision

This fragmentation was causing velocity problems: PRDs were written for individual features (GDrive ingest, X capture extension) without anchoring them in the product's core architecture, making it unclear whether they were building toward the right thing.

### Alternatives

1. **Continue as-is** — treat all projects as co-equal, keep writing PRDs for isolated features. Rejected because velocity is already suffering and there's no unifying vision.

2. **Build a new "factory dashboard"** — create a hosted UI for the tasks file as discussed earlier in the session. Deferred: the tasks file is the right interface, but the product architecture needs to be clear first so the tasks drive toward the right thing.

3. **Rewrite feed_analyser as capture instrument** — the X Capture Instrument PRD was heading this direction. Reassessed: the PRD was solving the right problem (getting X data in) but with the wrong architecture (standalone extension + server instead of a feeder into the survival infrastructure pipeline).

### Decision

The workspace is organized around one product — **Survival Infrastructure**, a personal action engine — with the following architecture:

**Two data sources + Two agents across two worlds:**

```
DIGITAL WORLD
├── Event Stream (Reality Layer)
│   Records: diary entries, voice notes, external data (X, Gmail, meetings)
│   Pipeline: capture → extraction → wiki (existing, working)
│   Feeder apps: feed_analyser (X), Gmail/GDrive ingest (to be built)
│
├── Instruction Library (Mind Layer)
│   Records: books, frameworks, maxims, principles — the user's digitized mind
│   Pipeline: ingest → chunk → embed → index → multi-stage retrieval
│   Status: NOT BUILT — this is the critical gap
│
└── Goal Agent (Agent 1 — Digital)
    Reads event stream → retrieves from instruction library → reasons → suggests with citations
    Status: NOT BUILT — depends on instruction library existing

PHYSICAL WORLD
└── User (Agent 2 — Human)
    Reviews suggestion → decides → acts → records outcome as new event
```

**The loop:**
1. Agent reads events → understands situation
2. Agent retrieves relevant instruction from the library
3. Agent reasons and produces a suggestion with citations
4. User reviews, accepts/modifies/rejects
5. User acts in the physical world
6. User records outcome as a new event → back to step 1

**Role of each project in the workspace:**

| Project | Role |
|---------|------|
| survival-infrastructure | The product — personal action engine, goal agent, all pipeline stages |
| feed_analyser | Feeder app — pulls X/Twitter data into the event stream |
| llm/ | Inference engine — powers extraction, synthesis, goal agent reasoning |
| workspace-portability | Backup/restore — ensures data portability and disaster recovery |
| mission-control | Monitoring — keeps infrastructure operational |
| resume | Output pipeline — toTweet → toBlog → toVideo from life data |
| headroom-pi | Compression proxy — optimizes LLM usage |
| software_factory | The meta-system that builds and operates all of the above |

### Rationale

1. **Product clarity drives velocity.** When every project knows its role (product vs. feeder vs. infrastructure), we can prioritize correctly. Survival infrastructure's build order is: instruction library → voice ingestion → goal agent → external feeders. Feeders are lower priority because the event pipeline already exists.

2. **Two-agent model captures reality.** The digital agent reasons but never acts. The human agent acts but needs guidance. This is not a limitation — it's the correct division of responsibility. The system proposes, the human disposes.

3. **Instruction library is the unlock.** The event pipeline works. But the goal agent is useless without a queryable instruction library. This is where the user's mind lives — frameworks, principles, books, everything they've learned. Building this first makes the goal agent possible.

4. **Voice ingestion is the highest-leverage input.** The user can record thoughts anytime (walking, driving, waking up). This feeds directly into the event pipeline. Always-available input > scheduled input.

### Consequences

**Things that become easier:**
- Prioritization: the build order is now clear (instruction library → voice → goal agent → feeders)
- PRD evaluation: every new feature is evaluated against "does this feed the event stream, the instruction library, or the goal agent?"
- Tasks file: tasks can be organized by which component they build toward
- The user's intuition about the X capture extension being wrong is validated — it was solving the right need (data ingestion) with the wrong architecture (standalone instead of feeder)

**Things that change:**
- The X Capture Instrument PRD should be re-evaluated: the question is not "build a Chrome extension" but "what's the simplest way to get X content into the survival infrastructure event stream?"
- The GDrive PRD is partially correct (instruction ingest) but incomplete (GDrive also contains events)
- Feed_analyser's role is defined: it's a feeder. Its architecture should reflect that — feed INTO the pipeline, not build a parallel system.
- The tasks file should reflect this architectural clarity going forward

**Things deprecated:**
- Treating feed_analyser as a standalone application with its own dashboard, database, and containers
- Building separate capture tools that don't feed into the survival infrastructure pipeline
- The "spec-driven process for all projects" task — deprecation was already noted in tasks.txt; this decision reinforces why

### Revision triggers

1. If the event pipeline proves insufficient for the volume/type of external data coming in (X, email, etc.), re-evaluate feeder architecture
2. If the user's workflow reveals that the two-agent model (suggest → decide → act → record) is too slow for certain use cases, consider faster loops
3. If the instruction library is built and the goal agent still produces low-quality suggestions, re-evaluate the retrieval architecture or the instruction source quality
4. If external constraints (e.g., X API shutting down, Gmail API deprecation) force a different data ingestion approach
