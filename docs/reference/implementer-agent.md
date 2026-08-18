# Implementer Agent — Artefact Map

**Why this document exists**: the implementer is deliberately NOT consolidated
into a single folder. Build artefacts, runtime artefacts, the worker's brain
(persona/skills), and its config each live where their ownership model says they
belong. Physical co-location is a human aesthetic and does not matter to an
agent. What matters is knowing, in one hop, where each artefact lives. This map
is that navigation aid — read it instead of grepping across the repo.

**What the implementer is**: the first component of the (deliberately abstract)
*assembly_line* — CI/CD, agents, sandboxes, testing. It is a decoupled
brain/hands pipeline: a **host driver** owns all git and a **disposable pi
worker** in a sandbox container implements a `Final` PRD against a host-side
worktree; the host authors the single commit, pushes, and raises the PR. The
user only inspects/accepts the PR.

**Core rule**: build vs runtime separation is intentional. The container, its
installed deps, and raw logs are **disposable**; only the commit/PR, the
archived report+decision, and the compact session evidence are **durable**.

---

## Build artefacts — source of truth (versioned)

| Artefact | Location |
|---|---|
| Host driver (orchestrates the whole run) | `bin/implementer-run.sh` |
| Image builder | `bin/sandbox-build.sh` |
| Task lifecycle transitions | `bin/transition-task.sh` |
| Driver unit suite (23 tests) | `bin/test-implementer-driver.sh` |
| Driver config (model, timeouts, respawn cap, image, roots, repo_map) | `config/implementer.json` |
| Worker persona / brief | `.pi/agents/implementer.md` |
| Worker in-container ops skill | `.agents/skills/implementer-ops/SKILL.md` |
| Worker artifact-save skill | `.agents/skills/implementer-save/SKILL.md` |
| Orchestrator (loop, bookkeeping PR, run manifest, pickup gate) | `bin/factory-run.sh` |
| Operator PR-set merge + complete transition | `bin/merge-pr.sh` |
| Image Dockerfile | `workspace-portability/container/Dockerfile` |
| Container entrypoint (session/`--continue` logic) | `workspace-portability/container/sandbox-entrypoint.sh` |
| Local container runner | `workspace-portability/container/run-sandbox.sh` |
| podman profile | `workspace-portability/profiles/factory-sandbox.conf` |
| Image provisioning | `workspace-portability/setup_pi.py`, `setup-guide.sh`, `portability_lib.py` |
| Portability design doc | `workspace-portability/docs/PORTABILITY_PLAN.md` |

**Built image**: `localhost/sandbox:latest` (rebuild with `bin/sandbox-build.sh`).

## Runtime artefacts — generated per run (NOT versioned)

| Artefact | Location |
|---|---|
| Run root (one dir per run) | `~/.factory/runs/<task-slug>-<ts>/` |
| Driver-generated task brief | `<run>/brief.md` |
| Implementer's deliverable (report + decision) | `<run>/outbox/` |
| pi session evidence (compact) | `<run>/sessions/` |
| Per-repo worktrees (multi-repo tasks) | `<run>/worktrees/<repo-key>/` |
| Run manifest (per-repo `{branch,pr,verdict,state}`, `bookkeeping_pr`, `revisions`, `outcome`) | `<run>/manifest.json` (mirrored into the bookkeeping PR body) |
| Full raw session trace + container logs | `<run>/session.jsonl`, `<run>/container-*.log` — **removed on successful delivery** (kept only under `IMPL_CLEANUP=false` or on failure for diagnosis) |
| Worktree clone (the implementation) | `<run>/worktree/` — **deps stripped on delivery** (`node_modules`, `venv*`, `__pycache__`); source + `.git` kept unless `KEEP_WORKTREE=0` |
| Injected env (`secrets.env`, **no GitHub tokens**) | `<run>/secrets.env` — deleted after the run |
| Archived report + decisions | `docs/implementations/<date>-<slug>/` |

## Sources of work (inputs)

| Artefact | Location |
|---|---|
| PRD that drives a run | `docs/prd-queue/<date>-<slug>.md` |
| Task file | `docs/tasks/<slug>.md` |
| Task list | `docs/tasks.txt` |

## Design intent / knowledge

| Artefact | Location |
|---|---|
| Harness architecture decisions (01–05) | `docs/knowledge/sessions/019fe7d2-…/decisions/` |
| False-kill liveness + session continuation (01), git-identity loss fix (02) | `docs/knowledge/sessions/019fecde-…/decisions/` |
| Knowledge index | `docs/knowledge/index.md` |

## Invocation

```
bin/implementer-run.sh <prd> <task> [--dry-run]
```

## Key invariants to honour

- The **implementer never runs git** (no init/add/commit/push). The host driver
  is the sole git author. This is a compliance guarantee, not just guidance.
- **No secrets** (GitHub tokens) ever enter the container env.
- Do not modify `docs/tasks*`, `docs/prd-queue/`, or the knowledge index.
- Continuation across a container respawn uses pi's **native session
  continuation** (`--session-dir /sandbox/sessions` + `--continue`), so the
  session id survives a kill; there is no PROGRESS.md.
- A fresh run-dir clone has no git identity — the driver configures it, so the
  host-authored commit actually lands (previous silent-loss failure mode).
