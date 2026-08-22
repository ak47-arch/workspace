## Decision: Evaluation department output feeds the context engine — not model finetuning

**Status**: accepted
**Date**: 2026-08-20 01:10
**Task**: [langfuse-agentic-operations](../../../../tasks/langfuse-agentic-operations.md)
**Project**: langfuse-agentic-operations
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Feedback target: the context engine — eval results flow into refining how the factory feeds agents context (progressive disclosure granularity, decision/knowledge summari

### Context

Decision 02 integrated evals as the fifth factory component (the evaluation department).
The user now states the strategic objective: **no model finetuning is intended**. The fruit of
the evaluation infrastructure feeds back into **refining the context engine itself**, and the
eval metrics (most, if not all) will be built **around the context engine** — because everything
downstream (project management, assembly line / implementer, reviewer) is scripts and
infrastructure components that consume the context engine, not learned models.

### Problem

Without an explicit feedback target, the evaluation department's metrics risk scattering across
surfaces (decision-loop, task-loop, app-quality, …) with no shared consumer. The factory needs a
single, explicit destination for eval signal so the department compounds toward one goal and
metrics are chosen for that goal — otherwise "continuous quality" is directionless and the
context engine stays a static snapshot rather than a learned, self-improving spine.

### Alternatives

1. **Metrics on every loop broadly** — the generic stance; risks surface-scatter and no coherent
   consumer for the signal.
2. **Finetuning-oriented metrics** — irrelevant here; explicitly out of scope (no finetuning).
3. **Context-engine-centric (chosen)** — a precise target: every eval surface's gold should
   ultimately inform how the context engine feeds agents (what context to surface, at what
   granularity, when, and at what cost), because the context engine is the load-bearing
   dependency for all downstream factory components.

### Decision

- **Feedback target**: the **context engine** — eval results flow into refining how the factory
  feeds agents context (progressive disclosure granularity, decision/knowledge summarisation,
  task-to-context mapping), not into model weights.
- **Metric construction**: new eval metrics are designed **around the context engine** — e.g.
  does a surface's artifact give an agent enough to proceed; is context lean enough (AGENTS.md
  footprint, decision summary fidelity); are knowledge entries retrieved/usable when needed; is
  the panel's SKIP fraction shrinking (the engine feeds more decisions checkably over time).
- **Surface discipline**: other surfaces (decision-loop, task-loop) remain as the deterministic
  substrate, but their panels are expected to expose **context-engine-relevant** signals (extra
  token footprint, unreachable links, unsummarizable decisions) rather than purely
  bookkeeping-family PASS/SKIP counts.
- **No finetuning**: explicitly out of scope; eval outcomes do not go toward tuning model
  weights.

### Rationale

The context engine is the only component every other factory component reads/writes (per
`docs/factory-context.md`: "Infrastructure spine. Every other component reads/writes it."). All
downstream behaviour — PRD gating, implementation, review, project management — is scripted
deterministic infrastructure; the quality lever that remains is *how well the factory feeds its
agents*. So the evaluation department's highest-value output is not "the model is bad", it is
"the context engine fed the wrong/right thing at the wrong/right cost".

### Consequences

- `docs/evaluations/README.md` and `bin/eval-*` panels will eventually grow context-engine
  metrics (footprint, retrieval, lean-ness) alongside the deterministic substrate.
- Metric design gate: a new eval surface is accepted if it can be framed as a context-engine
  question; surfaces that only measure deterministic PASS/FAIL of scripts remain secondary and
  are not the department's headline.
- The 22 claim checks / 96 SKIPs remain valuable as the substrate, but the "headline" of the
  department becomes: *does the context engine get better at feeding the factory's agents?*

### Revision triggers

- A finetuning program starts (then metrics must split: engine-feed metrics stay, weight-tuning as
  the second target).
- The context engine is replaced/renamed as a component (retarget the eval metrics accordingly).
- A chronic downstream quality problem that is clearly NOT caused by context (e.g. a deterministic
  script bug) — then the department also reports infrastructure-level findings, not just
  context-engine ones.
