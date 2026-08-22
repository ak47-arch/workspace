# PRD: Typed-Trail Integrity

**Date**: 2026-08-22
**Status**: [Final](./manifest.json)
**Owner**: software-factory workspace
**Task**: [typed-trail-integrity](../tasks/typed-trail-integrity.md)
**Session**: [session.jsonl](../knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/session.jsonl)
**Decisions**:
  - [02 — evaluation factory department](../knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/decisions/02-eval-factory-department.md)
  - [03 — evaluation feedback targets context engine](../knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/decisions/03-eval-feedback-target-context-engine.md)

## Problem statement

The context engine's charter is *"if you need anything, just follow the trail."* The
trail is the cross-reference chain: task → PRD → decision → session, each artifact
citing the next. Decision 03 makes this trail the quality lever — the engine's value is
how well it feeds its agents, and the feed is a *reference-chase*.

Measured against the real corpus, the trail is **not machine-followable deterministically**.
Three independent hygiene gaps compound:

1. **No stable artifact home** (signal 01). A PRD's canonical path changes when a task
   ships: `bin/transition-task.sh` physically `mv`s it from `docs/prd-queue/` to
   `docs/prd-archive/`. While the live dispatcher (`implementer-run.sh` `resolve_prd()`) is
   already content-driven (glob + grep for `**Status**: Final`), every *reference* to a moved
   PRD breaks silently. Measured: **8 of 10 completed task files still cite
   `prd-queue/<name>.md`** that now live in the archive.
2. **References are strings, not typed links** (signal 05). The cross-reference layers lean
   on bare/backticked string paths, which the agent must *reason* to follow (parse, resolve,
   disambiguate, handle staleness) instead of hopping deterministically. Measured: PRD layer
   **0 link targets / 213 backtick strings**; decision layer **0 links / 233+114 strings**;
   reference layer **54 backtick strings, 0 links**. Task files already do it right (67
   links) — the convention is uneven.
3. **No read-skip affordance** (signal 04). `docs/knowledge/index.md` promises each decision
   file carries a `**Summary**:` line so an agent can skip the body when the title resolves
   the question. Measured: **113 of 120 decision files lack `**Summary**:`**. Without it, a
   confused agent must open the body to resolve a "why" — exactly the wading cost the
   engine exists to avoid.

Shared root cause: **the disclosure trail is not a machine-checkable chain**. Every
string-path or moved file or missing summary is a point where the agent is forced to
reason or read prose, instead of taking a deterministic hop. "Follow the trail" is only true
when the trail is made of typed links, stable targets, and cheap read-skip markers.

## Solution overview

Make the disclosure trail **machine-followable by construction**: three linked changes that
share one principle — *references are typed links, targets are stable, and leaves carry a
cheap "can I stop here?" marker*.

**A. Stable PRD home (signal 01 → direction C).** Stop physically moving PRDs. Establish a
canonical, never-moving path and express lifecycle state as a **status field** on the
artifact, surfaced through a **routing manifest** (the engine's own idiom, used for
`knowledge/index.md` and the eval registers). `resolve_prd()` keeps its behavior — it
already globs a stable candidate set + greps `**Status**: Final` — so the pick contract holds.
No archived-path staleness is *possible* by construction.

**B. Typed-link trail (signal 05).** Adopt the task-file convention
(`[text](../relative/path.md)`, resolved from the file's own location) as the factory-wide
norm for every cross-artifact reference — PRD `Decisions:` front-matter, decision
`Session:`/`Task:` refs, knowledge index rows, reference prose, eval reports. A hygiene
check flags bare/backticked string paths pointing at `.md`/`.json`, so new-doc drift is
caught forward.

**C. Read-skip summary (signal 04).** Backfill the `**Summary**:` line on decision files
(mechanical, 7→120), and have the forward hygiene check flag a decision file that ships
without it.

All three are **falsifiable**: corpus scans have measurable before/after (~0 stale refs, ~0
string paths, 120/120 summaries); and a mis-disclosure injection (a deliberately broken link
or removed summary) must trip the register.

## User stories

1. As an **implementer**, when I'm handed a `Final` PRD, the PRD itself cites its governing
   decisions as typed links — I click through the trail once, deterministically, never
   regex-parsing a path.
2. As a **code-reviewer**, when I check a PR, the PRD + task + knowledge trail resolves at
   every hop and I can stop early at a readable summary instead of opening bodies.
3. As the **context-engine owner**, I can run one hygiene panel that fails on any
   not-machine-followable reference (string path, stale moved target, missing summary) — a
   systematic defect, not agent error.
4. As the **evaluator**, I can register these as drift-gold rows so a future disclosure-path
   regression trips the panel.

## Implementation decisions

- **One root cause, one fix.** 01/04/05 share "the trail isn't machine-checkable"; fold them
  so the fix is coherent rather than three patches. Signal 02 (COST historicity) stays
  separate by owner decision — it is a measurement concern, not a trail-integrity one.
- **Direction C for lifecycle.** Stable path + routing manifest (signal 01 verdict, recorded
  in `docs/research/signals.md`). Physical `mv` is the anti-pattern; A's premise (free
  directory glob) is false since the engine already pays a content-grep; B's rewrite-never
  -finishes trap is rejected.
- **Load-bearing ordering invariant.** `resolve_prd()` orders candidates by filename
  date-prefix (`yyyy-mm-dd-<slug>.md`, oldest-first) for "pick the oldest Final PRD." The
  manifest must retain a sortable ordering key or `--pick` regresses.
- **Typed links > strings.** Cross-reference = `[text](../relative/path.md)` resolved from
  the artifact's own location. Bare/backticked string paths are a reason-hop and are the
  defect.
- **Summary is a disclosure affordance, not an LLM grade.** Backfill is mechanical (from
  Context/Rationale); hygiene flags a missing summary without FAIL-ing the art.
- **Canonical path = `docs/prd/` (Q1 RESOLVED).** The stable, never-moving home is a
  neutral `docs/prd/` — a path that never implied state, so nothing must unlearn a
  "queue = active" meaning. `prd-queue/`/`prd-archive/` pass out of use.
- **Migration = one-time, corpus-consistent (Q2 RESOLVED).** All already-archived PRDs
  (langfuse-agentic-operations, implementer-delivery-failure-loud, etc.) `git mv` to
  `docs/prd/` once, and every inbound link is fixed in the same transaction. No
  forward-only split: retrospective tooling never wears a two-home resolver.
- **Link style / front-matter (Q3 RESOLVED).**
  - Cross-references are **typed relative links** resolved from the file's own location:
    hop with `..` up to `docs/`, then descend by path (task-file convention). No host
    absolute prefixes (broken across /workspace + /sandbox/worktree mounts), no
    repo-root links (also fragile in sandbox).
  - Front-matter fields become links: `Task` ↓
    `docs/tasks/<slug>.md`, `Session` ↓ `docs/knowledge/sessions/<uuid>/session.jsonl`,
    `Decisions` ↓ each decision md. `Date:` stays a bare atom (no target).
  - `Status` value links to the **routing-manifest row** for the slug — one authoritative
    state view (a file, not a directory), so lifecycle state is a hop, not a parse.

## Verification / testing

**Guidance: a check that can only ever PASS is can't-fail (register's anti-fabrication
rule). Post-Q1, stale `prd-queue/` citations are impossible by construction, so the
panel's falsifiable surface is the *injection*, not a passive count.**

- **Hygiene checks (NEW — not yet in `bin/eval-hygiene.py`; to be added):** corpus scan
  for (a) bare/backticked string paths to `.md`/`.json` in the PRD, decision, reference,
  eval layers — count → ~0 after migration; (b) decision files missing `**Summary**:`—
  count → 0/120; (c) no citations still pointing at `prd-queue/`/`prd-archive/` after all
  PRDs live in the stable `docs/prd/`.
- **Mis-disclosure injection (proves not can't-fail):** break a typed link / point a
  task at the wrong knowledge row / remove a `**Summary**:` / write a bare string path
  instead of a link — the corresponding register row must flip to FAIL. A row that cannot
  be made to flip is a dead can't-fail check and is removed, not shipped.
- **Ordering regression:** after migration, `resolve_prd() --pick` still returns the oldest
  `Final`+`prd-ready` PRD (filename sort semantic preserved by the manifest).

## Out-of-scope

- Signal 02 (COST historicity) — separate PRD, per owner decision.
- Signal 03 is absorbed by the semantic-probe PRD, not here.
- Model capability / finetuning (decision 03).

## Architecture

```
   docs/prd/                   ← stable home (canonical, never-moving path)
      <date>-<slug>.md         (lifecycle state = manifest, not location)
   docs/prd/manifest.json       ← routing manifest: slug → status (the file Status links to)
   docs/knowledge/index.md     — summary + typed-link leaf (decision read-skip)
        │
        ├─ bin/transition-task.sh → updates manifest (status field) — NO git mv
        ├─ bin/implementer-run.sh  → globs stable home + reads Status (unchanged
        │                           behavior; ordering key preserved)
        └─ bin/eval-hygiene.py     → flags string paths / missing summary /
                              stale-citation — typed-trail integrity panel
```

**Manifest data model** (`docs/prd/manifest.json`): the routing contract and the
load-bearing ordering invariant for `resolve_prd()`.

```json
{
  "version": 1,
  "prds": [
    {
      "slug": "typed-trail-integrity",
      "file": "2026-08-22-typed-trail-integrity.md",
      "status": "open",
      "ordering_key": "2026-08-22-typed-trail-integrity"
    }
  ]
}
```

The **ordering_key** is the filename date-prefix (`yyyy-mm-dd-<slug>`), preserving
`resolve_prd() --pick`'s "oldest Final first" ordering after migration. A PRD's `Status`
value resolves to `prds[].status` for its slug — the single authoritative state; no
consensus and no directory-as-state.

- `docs/prd/` — stable PRD home (post-migration)
- `docs/prd/manifest.json` — routing manifest: slug → lifecycle status (the `Status` link target)
- `docs/research/signals.md` — signal 01/04/05 records (source of the fold)
- `bin/transition-task.sh` — reworked: updates the routing manifest instead of `git mv`-ing
  the PRD out of the queue
- `bin/implementer-run.sh` — `resolve_prd()` globs the stable `docs/prd/` candidate set; ordering
  key preserved
- `bin/eval-hygiene.py` — extended with the typed-trail integrity checks
- `docs/knowledge/index.md` — decision summary affordance (already promised; now met)

## Acceptance (verification)

**Two-layer bar.** Counts are the goal; injection flips are the proof. A check must satisfy
both — if no mutation can make its count non-zero, it is can't-fail and is dropped, not shipped.

1. **Normative goal (post-migration):** the hygiene panel reports **0 string paths** and **0
   stale/mismatched citations** across the referenced layers (PRD/decision/reference/eval);
   **120/120** decision files carry `**Summary**:`.
2. **Falsifiable proof (the gate):** each check has at least one demonstrated mutation that
   trips it — a broken typed link, removed `**Summary**:`, bare string path, or stale
   `prd-queue/` target. A check that cannot be flipped to FAIL is dead weight and is removed.
3. The migration is a single transaction: stable-path move + manifest (no per-reference
   rewrite fire-and-chase).
4. `--pick` still selects the oldest `Final`+`prd-ready` (ordering-key form preserved).

**New checks (verification status)**: the three typed-trail checks (string-path,
summary-presence, stale/mismatch) do NOT exist in `bin/eval-hygiene.py` today — verified
2026-08-22: the file carries only master-merge, branch-protection, opensource/.env-ignore,
and secret-value scans. The typed-trail checks are new work; item 2's flips must be built
and demonstrated before the PRD advances to Final.

## Further notes

This is the typed-trail backbone the semantic probe (context-disclosure PRD) grades against.
Once the trail is machine-followable *by construction*, the probe's job becomes checking the
engine actually uses it — not that the links happen to line up.