# Research Signals — collected in-session, candidate work queued for the PRD pipeline

**Location**: in-session research signal bank. Signals here are **not** PRDs yet — they are
honest observations from research carried out interactively (not staged through the
implementer). Each signal states the observation, the evidence that raised it, the proposed
outcome, and the open question(s) to resolve before it becomes a PRD.

**Rule**: a signal earns a PRD only when (a) it is a *workflow/context-engine* improvement,
not a model capability matter (decision 03), and (b) it is *falsifiable* (has a measurable
before/after), so the implementation can be validated. Signals that are not falsifiable or
not workflow-shaped stay as research notes here rather than consuming PRD-pipeline capacity.

---

## Signal 01 — "PRD lifecycle state as a status field, not a physical move"

**Raised**: 2026-08-21, while building `bin/eval-context-semantic.py` (the context-disclosure
semantic probe).

**Observation**: `bin/transition-task.sh` archives a completed task's PRD by **moving the file**
from `docs/prd-queue/` to `docs/prd-archive/`. This couples an artifact's *identity* to its
*lifecycle state* (its canonical path changes when it ships). Downstream retrospective
consumers then must chase a moving target:

- Our own probe needed a **two-directory resolver** (queue + archive) just to find a bound PRD,
  purely because it had moved.
- COST measurement fell back to path-string tokens for the gate file because the **current
  disk path no longer holds the content**.
- **8 of 10 completed task files still cite `prd-queue/<name>.md` but the file now lives in
  `prd-archive/`** — a directly-measured stale-reference rate.

**Mechanism that raised it**: probe trace showed `docs/prd-queue/2026-08-13-code-review-agent.md
exists=False` even though the task is complete and REACH passed — the resolver had to look in
the archive.

**Proposed outcome**: express PRD lifecycle state as a **status field** (e.g. front-matter
`Status: open | in-prd | shipped`) on a **canonical, never-moving path**, not a physical `mv`.
Queue/archive *semantics* become a view/filter over that status, not a directory relocation.
Retrospective evals then find the artifact in exactly one place; stale references cannot
exist; the eval probe drops its resolver + content fallback.

**Honest tradeoff to name in any PRD**: physical move currently gives free "actionable" and
"shipped" directory reads; a status-field design pushes that filtering into every consumer.
This is a **cost transfer** (routing complexity onto consumers) not a pure win. For a factor
whose stated purpose is retrospective self-assessment (decision 02), the stable-path side wins —
breaking retrospective evals is the more expensive failure.

**Falsifiable before/after**: inject a stale PRD reference (or hide the PRD) — the probe must
flip that task's verdict. With a stable path, a stale reference is impossible by construction,
so the check is trivially true; the real test is "queue/archive views still produce the correct
actionable/shipped lists via status filter."

**Open questions before PRD**:
1. Canonical path: does a PRD live at `docs/prd-queue/` even when shipped (so the dir becomes
   "artifact home", not "not-yet-shipped"), or at a neutral `docs/prd/`?
2. Migration of the already-archived PRDs and their 8 stale task references — do we `git mv`
   them once to the canonical path and fix the links, or leave legacy and only change going
   forward?
3. Does the semantic probe keep its two-directory resolver as a *compat* path for historical
   tasks, or drop it once migration lands?

---

## Signal 02 — "COST (disclosure cost) must be a historical measure, not current-disk"

**Raised**: 2026-08-21, in the same session.

**Status**: collected.

**Observation**: the semantic probe's COST metric sums `est_tokens` (chars÷4) of *current disk
content* for every file read before the gate. But the agent read those files *during* the
session, when they held different content. So COST is an estimate of today's disclosure cost,
not the actual historical cost. And when a file has moved (Signal 01), COST cannot read it at
all and silently substitutes a path-string token count.

**Proposed shape**: harden COST by (a) resolving the artifact's actual on-disk location before
counting (kills the fallback), and/or (b) reconstructing the file's bytes **as of the session's
timestamp** via git history (`git show <session-ts>:<path>`), so the token count reflects what
was actually read. Or (c) drop token counting entirely and use **steps-to-gate** — the number
of read calls before the binding — which is robust, historical, and free of content drift.

**Open questions**:
1. Which consumers need COST as a *number*, vs. served by steps-to-gate?
2. If git-reconstruction, what is the overhead per session (blame/`log` on N files)? Worth it?
3. Should COST stay advisory forever (recommended given the register's
   no-fabricated-threshold rule) or is there a real budget to set against it?

---

## Supplementary observations (research notes, not yet signal-shaped)

- **Archive-as-move load**: the probe currently parses 37 retained session files (all present —
  no retention gap). The archive move is the *only* reason it needs dual-directory + fallback
  logic. If Signal 01 lands, probe complexity drops and these 37 become single-lookups.
- **COST ordering observation**: review-run sessions reach their PRD far earlier in the read
  stream (code-review-agent at read #4) than implementer sessions (implementation delivery at
  26–31 reads). This is a leanness hint, not yet a signal: "the engine surfaces bindings
  cheaply to reviewers, deep to implementers". Whether that is a defect depends on expected
  disclosure depth.

---

## Signal 03 — "Probe-contract artifact name inconsistent inside the PRD"

**Raised**: 2026-08-21, re-reading `docs/prd-queue/2026-08-21-context-disclosure-semantic-probe.md`
while resuming the semantic tier.

**Observation**: the PRD names the same declarative contract artifact two different ways:
`docs/evaluations/context-probes.json` (lines 79, 126) vs
`docs/evaluations/context-contracts.json` (line 157). Trivial to fix textually, but it's a
sign of unresolved shape — the contract's *canonical name and location* were not decided when
the PRD was written. If left, downstream implementers would chase a phantom path.

**Proposed outcome**: decide the canonical artifact name + location when formalizing the
contract (phase 1 of the PRD), then fix the PRD to reference it once. Consider a
`context-contracts.json` at `docs/evaluations/` (declarative matrix), keeping `bin/` free of
config.

**Open questions**: none — resolution is absorbed by formalizing the contract; the fix is a
one-edit rename sync.

---

## Signal 05 — "Cross-reference paths are strings, not typed links"

**Raised**: 2026-08-21, during the semantic-tier reframe discussion (navigation-integrity
probe).

**Observation**: the engine's charter is *"If you need anything just follow the trail"* — but
a large share of cross-references are **plain-string paths**, not typed links. An agent must
**reason** to follow them: infer that a backticked string is a path, resolve relative vs
workspace-root, handle moved files, then chase the string to disk. Each of those is an extra
reasoning hop for something the engine meant to be deterministic (follow the trail = follow
the link). Measured on the real corpus:

- **PRD files (19)**: **0 `.md` link targets, 213 backtick string paths** (18/19 files) —
  including the PRDs' own `Decisions:` front-matter, which strings decision paths that the
  knowledge layer indexes as links.
- **Decision files (120)**: **0 link targets, 233 backtick + 114 bare string paths**
  (118/120 files) — front-matter `Session:`/`Date:`/`Task:` refs are all strings.
- **Task files (27)**: 67 link targets, but **33 backtick + 107 bare strings** across
  26/27 files — links exist in `Artifacts:`/`Sessions:` but prose embeds string paths.
- **Reference files (4)**: 54 backtick strings, 0 links.

So the typed-link trail the engine implies is actually a **mixed landscape**: links are a
minority convention (task files) and the knowledge + PRD layers are pure string references.

**Why this costs**: every string-path is a *reasoning point* (parse, resolve, disambiguate,
handle staleness) where a typed link would be a *deterministic hop*. It compounds Signal 01
(moved files break string paths silently; a link target at least declares an intent) and is
the same family as Signal 04 (unannotated refs force reading prose). The probe's own
`binding_for_task` regex matching is a symptom — we had to parse strings because the docs
store them as strings.

**Proposed outcome**: adopt the task-file link convention as the factory-wide norm —
cross-references appear as typed `[text](relative/path.md)` links, never bare/backticked
strings. When the file lives under `docs/`, link from the file's own location (like the
task files' `../prd-queue/...`). Tooling can convert existing strings (the engine already has
a sed for the task-file case); a hygiene check can flag new bare strings.

**Falsifiable before/after**: scan the corpus for backtick/bare string paths pointing at
`.md`/`.json` files — count must go to ~0 for the referenced layers (PRD, decision,
reference) after migration, with typed links substituted.

**Open questions**: (1) relative-link style for `docs/prd-queue/` from decision files
(`../prd-queue/...` is wrong from `docs/knowledge/...` — needs the right depth, or absolute
`docs/...` links, or repo-relative links); (2) do we convert `Session:` front-matter to links
too, or is the string a deliberate "machine" field?

---

## Signal 04 — "Decision files lack the read-skip summary line"

**Raised**: 2026-08-21, checking the context engine's own stated convention.

**Observation**: `docs/knowledge/index.md` promises every decision file carries a
`**Summary**:` line so an agent can skip reading the body when the title resolves the
question. Measured: **113 of 120 decision files lack `**Summary**:`** — only 7 have it.

**Why this matters**: this is the engine's "read-skip" affordance — the cheap "can I stop
here?" check. Without it, the confused agent (your scenario) cannot decide from title alone
whether to open the body; it must read the full Context/Alternatives prose to resolve a
"why", which is exactly the wading cost the engine exists to avoid.

**Proposed outcome**: backfill `**Summary**: one-line from the Context/Rationale` for the 113
missing files (mechanical, falsifiable: 7→120 coverage), and add a hygiene/forward check that
a decision file without a summary is flagged (not FAIL — a disclosure affordance).

**Open questions**: (1) where the summary line is legal (front-matter right after metadata,
per the index convention); (2) whether the summary should be written by a human authoring
the decision, or generated at eval time from Context/Rationale (deterministic).

---

## State of this document

| Signal | Status | Ready for PRD? |
|---|---|---|
| 01 PRD-lifecycle-status | collected | needs the 3 open questions answered |
| 02 COST-historical | collected | needs decision on steps vs tokens + budget |
| 03 probe-contract-name | collected | absorbed by PRD phase-1 (artifact rename sync) |
| 04 decision-summary-gap | collected | ready for PRD: mechanical backfill, falsifiable |
| 05 string-paths-not-links | collected | needs decision on link style + front-matter refs |
| (supp 1) dual-dir cost | folded into 01 | — |
| (supp 2) reviewer-vs-impl depth | note | needs design input to become signal |

**Lifecycle**: When a signal's open questions are resolved, promote it to a PRD in
`docs/prd-queue/` and mark it here as `promoted` with the PRD link + date. Signals decided
non-actionable are marked `closed` with a one-line reason.