# Code Reviewer Agent — Artefact Map

**Why this document exists**: like the implementer it siblings, the code-reviewer
is deliberately NOT consolidated into a single folder. Build artefacts, runtime
artefacts, the worker's brain (persona/skills), and its config each live where
their ownership model says they belong. This map is the navigation aid — read it
instead of grepping across the repo.

**What the code-reviewer is**: the post-implementation gate on the assembly line.
It is a decoupled brain/hands pipeline structurally identical to the implementer:
a **host driver** owns all git mutations **and all `gh` calls** (resolve PR/repo,
post the PR comment, manage labels, lifecycle transitions), while a **disposable
read-only `pi` worker** in the sandbox container checks a raised PR against its
PRD — running the PRD's own verification commands plus deterministic and judgment
checks (including the ponytail over-engineering pass) — and writes a structured
APPROVE / REQUEST_CHANGES report. It **never** merges or completes a task; UAT +
user go-ahead stays with the user.

**Core rule**: the reviewer is **read-only**. It may run read-only git
(`diff/log/show/status`) to review `base...head` but must never mutate git state,
never run `gh`, and holds no GitHub credential. All mutations + PR comments are
driver-side. The six `opensource/ponytail` skills are injected reviewer-scoped via
`--skill` flags (never polluting shared `.pi/settings.json`).

---

## Build artefacts — source of truth (versioned)

| Artefact | Location |
|---|---|
| Host driver (orchestrates the whole review run) | `bin/review-run.sh` |
| Driver unit suite | `bin/test-review-driver.sh` |
| Driver config (model, timeouts, respawn cap, image, roots, repo_map, ponytail) | `config/reviewer.json` |
| Worker persona / brief | `.pi/agents/code-reviewer.md` |
| Worker in-container ops skill (checks + report schema + ponytail pass) | `.agents/skills/review-ops/SKILL.md` |
| Artefact map (this doc) | `docs/reference/reviewer-agent.md` |
| Implementer driver (gains the `factory:needs-review` PR label) | `bin/implementer-run.sh` |
| Ponytail skills (read-only, live opensource checkout; **not vendored**) | `opensource/ponytail/skills/{ponytail,ponytail-review,ponytail-audit,ponytail-debt,ponytail-gain,ponytail-help}` |

**Built image**: `localhost/sandbox:latest` — **reused unmodified** (same as the
implementer); deps are workspace-side.

## Runtime artefacts — generated per run (NOT versioned)

| Artefact | Location |
|---|---|
| Run root (one dir per review) | `~/.factory/runs/review-<slug>-<ts>/` |
| Driver-generated review brief | `<run>/brief.md` |
| Reviewer's deliverable (report + decisions) | `<run>/outbox/` |
| pi session evidence (compact) | `<run>/sessions/` |
| Worktree = **PR head** (read-only for the worker; base ref fetched) | `<run>/worktree/` |
| Injected env (`secrets.env`, **no GitHub tokens**, `PONYTAIL_DEFAULT_MODE=ultra`) | `<run>/secrets.env` — deleted after the run |
| Archived review report + decisions | `docs/code-reviews/<date>-<slug>/` |

> Archive root `docs/code-reviews/` is deliberately **distinct** from
> `docs/reviews/`, which holds PRD-gate reports (Decision 02).

## Sources of work (inputs)

| Artefact | Location |
|---|---|
| PRD the PR must satisfy | `docs/prd-queue/<date>-<slug>.md` |
| Task file (status gate) | `docs/tasks/<slug>.md` |
| Task list | `docs/tasks.txt` |

## Design intent / knowledge

| Artefact | Location |
|---|---|
| Review-agent decisions (01–04) | `docs/knowledge/sessions/019ff79e-…/decisions/` |

## Invocation

```
bin/review-run.sh [<pr>|--pick] [--dry-run]
# <pr>      repo#num, owner/repo#num, or full pull-request URL
# --pick    oldest open PR labeled factory:needs-review
# --dry-run no gh mutations (comment/label), no transitions, no workspace-root commit
```

## Key invariants to honour

- The reviewer **never mutates** git and **never runs `gh`**; the driver owns git
  + gh. No GitHub credential enters the container env.
- Read-only git (`diff/log/show/status`) **is** permitted — it is how the worker
  reviews `base...head`.
- A `REQUEST_CHANGES` verdict does **not** merge and does **not** complete the
  task; the PRD stays in `docs/prd-queue/` until user UAT + go-ahead. On APPROVE
  the driver transitions the task `in-progress → in-review` with the review session
  link.
- Do not modify `docs/tasks*`, `docs/prd-queue/`, or the knowledge index.
- Continuation across a container respawn uses pi's native session continuation
  (`--session-dir /sandbox/sessions` + `--continue`), so the session id survives a
  kill; there is no PROGRESS.md.
- The six ponytail skills load read-only from the live opensource checkout via
  repeatable `--skill` flags — no vendoring (Decision 04).