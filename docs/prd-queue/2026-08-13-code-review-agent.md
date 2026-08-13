# PRD: Code Review Agent — autonomously review factory-raised PRs against their PRD

**Date**: 2026-08-13
**Status**: Final
**Owner**: software-factory
**Task**: code-review-agent
**Session**: `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/01-code-review-manual-trigger.md`
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/02-code-review-archive-location.md`
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/03-review-worker-read-only-git.md`
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/04-ponytail-review-worker-skills.md`

## Problem statement

The assembly line has a **readiness gate before implementation** (the `prd-reviewer`
checks a plan is routeable) and a **hands** stage that builds it (the `implementer`
raises the PR). But after the PR is raised, the **user is the sole code-review
gate** — the same manual pass performed on PR #1 (`extension-inline-agent`) by hand.
This is the last fully-manual step in the pipeline.

Today that pass is ad-hoc: fetch the PR head, diff it against the PRD, run the PRD's
verification commands, eyeball the stories, reason about intent. Doing it manually
doesn't scale to many PRs and, critically, the step never gets *better* — nothing
records what a thorough review looks like or accumulates checks over time. There is
no automation to extend.

What's missing is a **post-implementation review agent**: a sibling of the
implementer that picks up a raised PR (manually triggered, same pattern) and checks
it against its PRD with deterministic + judgment steps — including running the PRD's
own verification commands — and produces a structured report. It must be structured
and versioned so the review checklist can grow more robust over time, and it must
**never** merge or complete a task (UAT + user go-ahead stays with the user).

## Solution overview

A new agent, structurally identical to the implementer's brain/hands pipeline: a
**host driver** owns git/GitHub mutations, a **disposable read-only `pi` worker** in
the existing sandbox does the reviewing, and the same run-dir / outbox / archive /
session-continuation machinery is reused. It is triggered manually exactly like the
implementer: `bin/review-run.sh <pr>` (plus `--pick` and `--dry-run`).

The driver resolves the PR → repo (via `config/reviewer.json` repo_map) → task slug
(from title `[factory] <slug>: …` or branch `factory/<slug>/<ts>`) → PRD, checks out
the PR head read-only, and hands a brief to the worker. The worker runs the PRD's
`Testing decisions` commands and two classes of checks — **deterministic** (PR
metadata, scope containment, scope ⊂ PRD file-map, story→diff coverage, no secrets,
implementer's archived report vs actual diff) and **judgment** (story intent,
decision conformance, edge cases, precise UAT-gap list) — and writes a structured
report mirroring the prd-reviewer's format. The driver posts the report to the PR,
archives it, and transitions the task.

The review includes a **Ponytail over-engineering pass**: the worker loads
`opensource/ponytail`'s skills (read-only, via pi `--skill` flags) and runs
`ponytail-review` over the diff at `ultra` mode — findings (stdlib/native/yagni/
delete/shrink) are reported as an **advisory subclass** (never alone blocking),
and existing `ponytail:` shortcut markers in changed files are harvested into the
report's UAT section. This ships the over-engineering review as a first-class,
versioned check instead of the untracked prose found in the implementer.

Review checks live in the **versioned `review-ops` skill + `code-reviewer` persona**
(not baked into the driver), so adding a robustness step is an edit to the skill.
The worker is read-only: it never commits, and the container holds no GitHub token.

## User stories

1. As a factory operator, I can trigger a code review of a specific PR with
   `bin/review-run.sh <pr>` (repo#number or URL) and receive a structured report
   back without doing any manual review.
2. The driver resolves the PR's repo, task slug, and PRD from PR metadata
   (title/branch), so I never specify the task manually.
3. The worker checks out the PR head read-only, diffs `base...head`, and **runs the
   PRD's verification commands**, recording pass/fail per command with evidence.
4. The worker runs deterministic checks (metadata sane; scope ⊆ PRD file-map; no
   secrets / stray deps; every PRD story maps to diff evidence; the implementer's
   archived report matches the actual diff) and judgment checks (story intent,
   PRD-decision conformance, edge/error paths, over-engineering via
   `ponytail-review`, UAT gaps).
5. The report is structured (per-story + per-check PASS/FAIL with evidence,
   blocking vs advisory findings, verdict) and is both posted to the PR as a comment
   and archived to `docs/code-reviews/<date>-<slug>/`.
6. A `REQUEST_CHANGES` (blocking) verdict does **not** merge and does **not**
   complete the task; the PRD stays in `docs/prd-queue/` until user UAT + go-ahead.
7. On a successful review the driver transitions the task `in-progress → in-review`
   and links the review session on the task file (PRD still stays in the queue).
8. The reviewer reuses the existing `sandbox:latest` image and mirrors the
   implementer config shape (`config/reviewer.json`), so it is configurable with its
   own persona, skills, and extensions.
9. The deterministic + judgment checks are declared in the versioned
   `review-ops` skill / `code-reviewer` persona, so extending review robustness is a
   skill edit, not a driver change.
10. The reviewer is read-only: no commits/writes to the target repo, and no GitHub
    credential enters the container; all mutations + PR comments are driver-side.
11. The review includes a **Ponytail over-engineering pass**: the worker has the
    six `opensource/ponytail` skills (`ponytail`, `ponytail-review`,
    `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`) loaded
    via `--skill` at `ultra` mode; it reviews the `base...head` diff with
    `ponytail-review` (`L<line>: <tag> <what>. <replacement>.` findings),
    reports them as advisory (never blocking alone), and harvests existing
    `ponytail:` shortcut markers in changed files into the report's UAT section.

## Implementation decisions

- **Pipeline mirror**: `bin/review-run.sh` mirrors `bin/implementer-run.sh` —
  run-dir (`~/.factory/runs/review-<slug>-<ts>/`), brief/outbox, podman sandbox
  (reuse `sandbox:latest`), native session continuation (`--continue`) across
  respawns.
- **Trigger**: manual `review-run.sh <pr>`; `--pick` selects the oldest open PR
  labeled `factory:needs-review` as convenience. **No polling / webhook / timer** in
  v1 (deferred). The implementer **will tag** PRs `factory:needs-review` on create
  (one-line `--label` addition, see file-tree diff) as inert metadata that makes
  `--pick` and future automation possible; the driver ensures the label exists
  once (`gh label create --force`) so `--label` never fails on a fresh repo.
- **Worktree = PR head** (delta from implementer, which checks out the manifest
  branch to write). Driver clones the repo, checks out the PR head, and fetches the
  base ref so the worker can `git diff base...head` read-only.
- **Git rule differs deliberately**: the reviewer MAY run read-only git
  (`diff/log/show/status`) — it needs them to review — but must never mutate and
  never run `gh`. The driver owns all git mutations, the PR comment, labels, and
  transitions.
- **No secrets in container**: driver does all `gh` calls host-side (resolve repo,
  posted by the driver after the run, labels, transitions), same as implementer.
- **Report schema** fixed (per-story + deterministic + judgment + findings +
  verdict), mirroring the prd-reviewer output format, so check additions never break
  consumers.
- **Archive**: `docs/code-reviews/<date>-<slug>/` — deliberately **distinct** from
  `docs/reviews/`, which already holds PRD-gate reports.
- **Check list location**: v1 keeps checks in the versioned `review-ops` skill +
  `code-reviewer` persona (YAGNI — no config-based check registry yet; editable later
  without changing output).
- **Lifecycle**: driver transitions the task `in-progress → in-review` + links the
  review session after a successful review; the PRD remains in the queue until UAT.
- **Ponytail pass** (Decision 04): the worker loads the six `opensource/ponytail`
  skills via repeatable `--skill` flags pointing at
  `/workspace/opensource/ponytail/skills/` (read-only mount; live from the opensource
  checkout — no vendoring, updates flow via workspace-portability).
  `PONYTAIL_DEFAULT_MODE=ultra` is in the reviewer env allowlist. `review-ops`
  gains the over-engineering judgment check (`ponytail-review` on `base...head`,
  advisory subclass, **explicitly run at ultra** — instruction-level, not reliant
  on the env var, since the interactive extension is out of scope) + `ponytail-debt`
  harvest. The interactive pi-extension and
  `ponytail-mcp` are **not** wired into the worker (headless UI risk / pi injects
  skills natively).

## Testing decisions

Seams, mirroring the implementer's driver-suite approach (`bin/test-implementer-driver.sh`):

- **Driver unit** (new `bin/test-review-driver.sh`, fixture-driven, `gh` + git
  mocked/call-counted):
  - arg parsing — `repo#num`, `repo` slug shorthand, full URL; `--pick`; `--dry-run`.
  - repo resolution via `config/reviewer.json` repo_map.
  - task-slug resolution from PR title and from branch name.
  - run-dir layout + brief/outbox contract (paths, UUID, rules).
  - worktree checkout of the PR head with the base ref fetched.
  - archive to `docs/code-reviews/<date>-<slug>/` and PR-comment invocation.
  - transitions (in-progress → in-review + session link), simulated under `--dry-run`.
- **Worker (in-container)**: against a synthetic fixture PR (a throwaway branch on a
  scratch repo with a small PRD), the worker produces a report with per-story +
  per-check verdicts and runs the fixture PRD's verification commands (mock where
  network is unavailable), recording exactly what runs and what is deferred.
- **Non-deterministic**: verdict sanity — an APPROVE-shaped fixture yields APPROVE;
  a REQUEST_CHANGES-shaped fixture (blocking finding) yields REQUEST_CHANGES.
- **Guardrails**: suite asserts the worker made no commits (clean worktree), no
  `gh` call from the container, and no token env is set in the container.
- **Ponytail seams**: driver suite asserts the six `--skill` ponytail flags and
  `PONYTAIL_DEFAULT_MODE=ultra` appear in the podman invocation; a worker fixture
  against an over-engineered synthetic PR must produce `ponytail-review` findings
  in the expected `L<line>: <tag> …` format inside the report; guardrail: advisory
  over-engineering findings alone must never flip the verdict to
  REQUEST_CHANGES.
- **Regression**: existing implementer driver suite + transition suite still pass;
  sandbox image reused unmodified.

## Out-of-scope

- **Auto-trigger** (polling, webhook, timer, GitHub Actions): deferred — manual
  trigger only in v1.
- **Merge / auto-merge** and **task completion / UAT sign-off**: always the user.
- **Code changes in the target repo**: the reviewer never writes code; it reports.
- **Config-driven check registry** (`config/reviewer.json` `checks[]`): deferred;
  v1 declares checks in the versioned skill/persona.
- **Reviewing non-factory (user-authored) PRs**: supported only via the optional
  `--pick` label seam; no bespoke review surface for them in v1.
- **Ponytail interactive pi-extension + `ponytail-mcp` in the review worker**:
  deferred — v1 wires only the six skills. The extension stays available for
  interactive use from `opensource/`.
- **Implementer-side ponytail upgrade** (prose → real skills): a separate tracked
  task, not part of this PRD.

## Architecture

### System diagram

```
        trigger (manual)                ┌───────────────────────────── host ─────┐
        bin/review-run.sh <pr> ───────▶ │ driver: resolve → run-dir → worktree    │
            │  ┌──────────────┐         │      (PR head checkout, base fetched)   │
            │  │ config/       │         │   ┌─────────────────┐   ┌────────────┐  │
            │  │ reviewer.json │         │   │ brief.md        │   │ outbox/    │  │
            │  └──────────────┘         │   │ PR·PRD·slug·base │──▶│ report.md  │  │
            ▼                           │   └─────────────────┘   └────────────┘  │
   ┌───────────────────┐  podman run    │            │  session --continue (respawn)
   │ GitHub             │◀──────────────│   ┌─────────────────────────┐           │
   │ PR (needs-review)  │               │   │ sandbox worker (pi)     │           │
   │  ▶ factory/code-   │    gh pr      │   │  .pi/agents/             │           │
   │    comment (drive) │◀──────────────│   │   code-reviewer.md       │           │
   │  ▶ labels/transit. │               │   │  .agents/skills/review-ops│          │
   └───────────────────┘               │   └─────────────────────────┘           │
                                       └──────────────────────────────────────────┘
```

### Data flow (one run)

1. Operator runs `bin/review-run.sh <pr>` (repo#num / URL) or `--pick`.
2. Driver resolves repo via `repo_map`; parses task slug from PR title or branch
   `factory/<slug>/…`; finds task file + PRD.
3. Driver creates `~/.factory/runs/review-<slug>-<ts>/`; clones the repo, checks out
   the PR head into `<run>/worktree`, fetches the base ref.
4. Driver writes `<run>/brief.md` (PR url, PRD path, task slug, review-session UUID,
   base/head refs, outbox paths, rules) — no secrets.
5. Driver `podman run`s the worker (`--append-system-prompt code-reviewer.md`,
   `--session-dir` + `--continue`), streaming to `<run>/container-*.log`.
6. Worker reads the PRD (ro `/workspace`) and the checkout; runs deterministic +
   judgment checks and the PRD's verification commands; writes
   `<run>/outbox/report.md`; exits 0 (or 1 on partial).
7. Driver reads the outbox: archives to `docs/code-reviews/<date>-<slug>/`, posts the
   report to the PR (`gh pr comment`), updates the `factory:*` label, sorts the
   knowledge index, commits + pushes the workspace root.
8. On successful review the driver `transition-task.sh <slug> --to in-review` with
   the review session link; the task file records the review session; the PRD stays
   in queue.

### Interfaces / contracts

- **Config** `config/reviewer.json` (mirrors `implementer.json`): `repo_map`,
  `model`, `timeout_sec`, `respawn_cap`, `env_allowlist`, `image` (`sandbox:latest`),
  `runs_root`, `reviews_root` (`docs/code-reviews`),
  `ponytail: { skills_dir, default_mode }`
- **brief.md** (contract): PR url · PRD path · task slug · review-session UUID ·
  worktree path · base/head refs · rules (read-only git only, no `gh`, no secrets) ·
  PRD verification commands · outbox paths.
- **outbox/report.md** (contract): per-story PASS/FAIL + evidence · per-check
  PASS/FAIL + evidence (deterministic + judgment) · verification results (what ran /
  what remains) · blocking vs advisory findings · verdict (APPROVE /
  REQUEST_CHANGES) · UAT hand-off list.
- **podman run** (signature, mirrors implementer): `pi --mode json -p
  --append-system-prompt /workspace/.pi/agents/code-reviewer.md --session-dir
  /sandbox/sessions [--continue] …` in `sandbox:latest`, host mounts `/workspace`
  (ro) + run dir (rw worktree/outbox/sessions).

### Data model changes

- `docs/code-reviews/<date>-<slug>/report.md` (+ brief, decisions) — new archive root.
- Task file `docs/tasks/<slug>.md` gains a review-session entry under `## Sessions`.
- `docs/tasks.txt` — task line annotated `[code-review-agent]`, moved to Queued on
  prd-ready.
- `config/reviewer.json`, `.pi/agents/code-reviewer.md`,
  `.agents/skills/review-ops/SKILL.md`, `docs/reference/reviewer-agent.md` — new.
- `docs/factory-context.md` workforce roster + pointer to the
  `docs/reference/reviewer-agent.md` artefact map — updated.

## Program Design

### File-tree diff

```
bin/review-run.sh                     (NEW) host driver, mirrors implementer-run.sh;
                                       pi invocation carries six `--skill` ponytail
                                       flags + `PONYTAIL_DEFAULT_MODE=ultra`
bin/test-review-driver.sh             (NEW) driver unit suite (fixture-driven)
config/reviewer.json                  (NEW) config (mirrors implementer.json;
                                       `ponytail: { skills_dir, default_mode }`)
.pi/agents/code-reviewer.md           (NEW) worker persona (read-only reviewer)
.agents/skills/review-ops/SKILL.md    (NEW) run contract (checks + report schema;
                                       includes the ponytail over-engineering
                                       judgment check + debt harvest)
docs/reference/reviewer-agent.md      (NEW) artefact map
docs/factory-context.md               (EDIT) roster + assembly_line pointer
bin/implementer-run.sh                (EDIT) `gh pr create` gains
                                       `--label factory:needs-review` (after
                                       `gh label create --force` once)
docs/tasks/code-review-agent.md       (NEW) task file
docs/prd-queue/2026-08-13-code-review-agent.md   (NEW) this PRD
docs/reviews/                         (UNCHANGED — holds PRD-gate reports)
```

### Call-stack trees

```
review-run.sh main()
 ├─ resolve_pr()            # repo#num / url → repo, pr_number
 ├─ resolve_slug()          # PR title / branch → slug
 ├─ resolve_repo()          # slug.Project → repo via repo_map
 ├─ prepare_run_dir()       # mkdir run dir; clone; checkout PR head; fetch base
 ├─ write_brief()           # brief.md contract (no secrets)
 ├─ run_container()         # podman run (respawn via --continue, liveness)
 ├─ archive()               # outbox → docs/code-reviews/<date>-<slug>/
 ├─ post_pr_comment()       # gh pr comment (host)
 ├─ update_label()          # gh label factory:reviewed-ok / review-blocked
 └─ transition()            # transition-task.sh <slug> --to in-review --session …
```

Worker (`code-reviewer.md` + `review-ops`):
```
read brief → orient (ro /workspace PRD + <run>/worktree checkout)
 → diff base...head (read-only git)
 → run PRD verification commands
 → run deterministic checks   → PASS/FAIL + evidence
 → run judgment checks        → PASS/FAIL + reasoning
 → assemble outbox/report.md  → per-story, findings, verdict, UAT list
 → exit 0 (report) / exit 1 (partial)
```

### Key types and signatures

```
# driver
review-run.sh [<pr>|--pick] [--dry-run]
# config
{ repo_map, model, timeout_sec, respawn_cap, env_allowlist, image,
  runs_root, reviews_root, ponytail: { skills_dir, default_mode } }
# ponytail skills (read-only, live opensource checkout)
#   /workspace/opensource/ponytail/skills/{ponytail,ponytail-review,
#     ponytail-audit,ponytail-debt,ponytail-gain,ponytail-help}
# brief.md (contract)
#   PR url · PRD path · task slug · review-session UUID · worktree path
#   base ref · head ref · rules (read-only git, no gh, no secrets)
#   PRD verification commands · outbox paths
# outbox/report.md (contract)
#   per-story: PASS/FAIL + evidence
#   per-check (deterministic + judgment): PASS/FAIL + evidence/reasoning
#   verification results (ran / remains) · blocking vs advisory findings
#   verdict: APPROVE | REQUEST_CHANGES · UAT hand-off list
# podman run (signature)
#   pi --mode json -p \
#      --skill /workspace/opensource/ponytail/skills/ponytail \
#      --skill /workspace/opensource/ponytail/skills/ponytail-review \
#      --skill /workspace/opensource/ponytail/skills/ponytail-audit \
#      --skill /workspace/opensource/ponytail/skills/ponytail-debt \
#      --skill /workspace/opensource/ponytail/skills/ponytail-gain \
#      --skill /workspace/opensource/ponytail/skills/ponytail-help \
#      --append-system-prompt /workspace/.pi/agents/code-reviewer.md
#      --session-dir /sandbox/sessions [--continue] …
#   (env carryover via --env-file: PONYTAIL_DEFAULT_MODE=ultra from
#    config/reviewer.json env allowlist)
```

### Build / run notes

- Reuse the built `sandbox:latest` image unchanged (deps are workspace-side).
- `gh` runs only on the host; the worker never sees a GitHub token (matches
  implementer compliance invariant).
- The review worker is **read-only**: it may `git diff/log/show/status` but must not
  write/commit and must not run `gh`. The driver enforces this via the brief rules +
  the read-only persona.
- On a partial review (container failure), the driver still archives the partial
  report, leaves the task `in-progress`, and reports exit 1 — mirroring the
  implementer's failure-path contract.
