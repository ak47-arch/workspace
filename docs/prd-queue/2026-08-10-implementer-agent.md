# PRD: Implementer Agent — sandboxed autonomous implementation (harness + cattle container, workspace-portability integration)

**Date**: 2026-08-10 20:59
**Status**: Draft
**Owner**: software-factory
**Task**: implementer-agent
**Session**: `docs/knowledge/sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/decisions/01-implementer-harness-host-cattle-container.md`
  - `docs/knowledge/sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/decisions/02-durable-state-host-session-outside-container.md`
  - `docs/knowledge/sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/decisions/03-sandbox-on-workspace-portability.md`
  - `docs/knowledge/sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/decisions/04-implementer-runtime-config-model-skills-extensions.md`
  - `docs/knowledge/sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/decisions/05-implementer-lifecycle-traceability.md`

## Problem statement

PRDs in `docs/prd-queue/` reach **Final** after the review gate, but nothing picks them up: the assembly line stops at the PRD. The user must manually implement every plan — the factory loop ("user interacts only with the product layer, everything else is automation") is broken at the implementation stage. The `extend-pm-assembly-line` task explicitly deferred this: "the autonomous implementation agent is Part 2, the assembly line's first real component" (decision `03-scope-boundary-ci-and-implementer-deferred-to-part2`).

Two hard constraints shape the solution:

1. **Container ephemerality is the observed failure mode.** A prior attempt ran agents inside containers and "containers suddenly go down for no reason and so does everything inside them" — all state (worktree, session, decisions) vanished with the process. Anthropic's managed-agents engineering (brain/hands decoupling, durable session outside the container, containers as cattle re-initialized by a provision recipe) is the proven fix for exactly this failure, and this workspace has lived it.
2. **The environment must be cloud-portable.** The workspace is moving its entire infra to the cloud. The sandbox therefore cannot be a throwaway local hack — it must be built on `workspace-portability/` (the existing manifest-driven env-setup system: repo clones, profiles, secrets strategy, bootstrap flow) so the identical worker image and driver run on a cloud runtime later.

The implementer must also run with **its own special skills and extensions** (ponytail's lazy-senior-dev discipline, the factory's `langfuse-tracing` observability, a factory run-contract skill), which requires an execution environment that supports scoped pi configuration — precisely what the sandbox provides.

## Solution overview

A two-part implementer following the **decoupled brain/hands** pattern:

- **Harness — host-side driver** (`bin/implementer-run.sh`): deterministic orchestration *outside* the container. Picks a `**Status**: Final` PRD, resolves the target repo, creates a **host-side git worktree** (durable), writes a task **brief**, provisions the sandbox container (bind mounts, env), **streams the implementer's event output live to a host-side session log**, watches liveness, **respawns** the container on abnormal death (cattle), and on success pushes the worktree branch, raises a PR via `gh`, archives the run report + decisions, and runs lifecycle transitions. All state exits through git; the container holds nothing durable.
- **Hands — sandbox container** (cattle): a podman/OCI image built via workspace-portability containing pi, git, node, and a scoped pi config (`defaultProjectTrust=always`, `langfuse-tracing` enabled). It mounts the host workspace **read-only** at `/workspace` (docs/PRDs/skills/extensions) and a run dir **read-write** at `/sandbox` (worktree, outbox). It runs one headless `pi` process — the implementer agent — whose system prompt embeds **ponytail** as an always-on working style plus an **implementer-ops** run contract. **No GitHub credentials ever enter the container**; the driver owns push/PR.

The implementer's special set: model `openrouter/deepseek/deepseek-v4-flash-0731` (the factory's current model; per-run override via env), extension `langfuse-tracing`, directive `ponytail` (embedded, full mode), skill `implementer-ops` (the run contract).

Locally the run uses bind-mounted host repos (**no cloning** — fastest possible); in the cloud the same image + driver run against a durable worker workspace provisioned by portability's minimal targeted restore (a new `factory-sandbox` profile — repos-only, no services/models/snapshots).

## User stories

1. As a factory operator, when I run the driver (no args ⇒ `--pick`), it deterministically selects one `**Status**: Final` PRD from `docs/prd-queue/` (oldest first; skips in-flight tasks) and prints the selection before doing anything else.
2. The driver maps the PRD to its target repo (task file `**Project**` → repo path in the portability manifest; `software-factory`/root tasks → `.`) and creates an isolated git worktree at `~/.factory/runs/<slug>-<ts>/worktree/` on a branch `factory/<slug>/<ts>` from the repo's manifest branch.
3. When I run the sandbox, the container starts with `/workspace` (host workspace) mounted **read-only**, `/sandbox` (run dir) read-write, and an environment containing **only** LLM + Langfuse credentials — no GitHub token, no host secrets. The implementer `pi` process resolves its brief, the ponytail working style, the `implementer-ops` skill, and `langfuse-tracing` (a new trace appears in Langfuse during the run).
4. The implementer implements every user story in the PRD inside the worktree, **committing after each completed story/unit** (commit-early), and its full stdout event stream is captured live by the driver into the host-side session log (`docs/knowledge/sessions/<impl-uuid>/session.jsonl`).
5. If the container dies mid-run (kill, OOM, runtime fault), no committed work is lost: the driver respawns a fresh container against the same run dir and brief (up to N times, default 3); the implementer resumes from the committed worktree state. The kill is survivable.
6. On success, the driver reads the implementer's outbox, archives the **run report + decisions** into `docs/implementations/<date>-<slug>/` (host, committed), transitions the task `prd-ready → in-progress` (it **stays in-progress until the PR is merged**, per the existing archive gate), pushes the worktree branch, and raises a PR (`base` = the repo's manifest branch) with title/body from the brief + report. The PRD **stays in the queue**.
7. The implementer physically cannot modify `docs/tasks/`, `docs/tasks.txt`, or `docs/prd-queue/` — those are inside the read-only `/workspace` mount. There is no mechanism path to them.
8. On failure, the driver transitions the task back to `prd-ready` (still queued and pickable), writes a partial report, and exits non-zero. No PR is raised. Re-running picks it up again.
9. The same image + driver work identically in a cloud runtime: the worker provisions its durable workspace via the `factory-sandbox` portability profile (minimal targeted `--repos` restore into durable storage) and then runs the same driver; only the workspace *source* differs from the local bind-mount.
10. A **disposable sample PRD** (small synthetic feature put through the review gate to Final) runs the full loop in `--dry-run` mode (worktree + report + session produced, **no push, no PR**), is inspected, and is then **discarded without residue** (PRD, task file, tasks.txt line, run dir removed).

## Implementation decisions

- **Two-part split, harness-outside**: host driver = deterministic orchestrator + all git mutations; container = one headless implementer pi process (creative work only). Push/PR/lifecycle commits are driver-only, mechanism-level (no repo credentials inside the container). Decision 01.
- **Durable state on host**: worktree, streamed session log, outbox, report, decisions all live under `~/.factory/runs/<slug>-<ts>/` and `docs/implementations/` on the host — nothing durable inside the container. Commit-early convention makes resume natural. Decision 02.
- **Sandbox via workspace-portability**: new `profiles/factory-sandbox.conf`; pi installation moves in-scope in portability (a setup step following the existing per-repo pattern); container definition + host wrapper + Dockerfile live in `workspace-portability/container/`; the run-time clone of the workspace root is **replaced by a read-only bind mount locally**; the targeted minimal-restore path is the cloud worker's provisioning mechanism. Decision 03.
- **Implementer runtime set**: model `openrouter/deepseek/deepseek-v4-flash-0731` (the session's own model; per-run `IMPLEMENTER_MODEL` env override); extension `langfuse-tracing` (via the workspace root's `.pi/settings.json`, discovered from `cwd=/workspace`); **ponytail embedded in the system prompt as an always-on directive** (full mode — load-on-demand is unreliable for an autonomous worker; `opensource/ponytail` pulled to upstream `2ed6c52` is the versioned source); new `implementer-ops` skill = the run contract (brief, worktree, commit-early, verification protocol, report format, no-docs/no-secrets rules). Image global settings: `defaultProjectTrust: "always"` (headless pi silently ignores project resources otherwise). Decision 04.
- **Lifecycle/traceability**: driver transitions `prd-ready → in-progress` at pickup; task stays `in-progress` until the PR merges; PRD stays in the queue (existing archive gate). Implementation session = driver-captured JSONL stream at `docs/knowledge/sessions/<impl-uuid>/session.jsonl`, linked on the task file. Decisions: implementer writes candidate decision markdown into its outbox (`implementer-save` semantics, session dir passed explicitly — the `save-knowledge` `ls` heuristic is blind headless); the **driver** appends index entries deterministically (`sort-knowledge-index.py`) — the model never touches `docs/knowledge/index.md`. Decision 05.
- **Acceptance model**: staged — (0) build/boot probes, (1) `--dry-run` on a disposable sample PRD incl. the mid-run `podman kill` resilience test, (2) live run on `extension-inline-agent` raising a real PR. Sample PRD discarded after stage 1.

## Testing decisions

Seams, highest to lowest:

- **Full-loop dry run (integration, primary seam)**: stage 1 runs the entire pipeline against a disposable sample Final PRD with `--dry-run`; pass = worktree diff sane, session log streamed, report + outbox decisions present, resilience kill test passed, discard clean.
- **Container boot probe**: the image boots, `pi --version` works headless, project trust resolves, skills/extensions discover (`pi` reports them), and a Langfuse trace appears during a probe run.
- **Driver unit-level**: `/bin/bash -n` + shellcheck; `resolve_prd`/`resolve_repo`/brief-writer covered by a fixture queue in a temp dir (no git needed), mirroring `bin/test-transition-task.sh` style.
- **Lifecycle**: `bin/test-transition-task.sh` still passes; a dry-run transition (`prd-ready → in-progress`) updates task file + tasks.txt placement correctly.
- **Live end-to-end (stage 2)**: real PR raised on `feed_analyser` for `extension-inline-agent`; task at `in-progress`; PRD still in queue; review/test of the PR itself is **out of scope** (future stage).
- **Regression**: this task's own implementation is built in-session; the factory's existing bookkeeping tests keep passing.

Concrete commands: `bin/sandbox-build.sh && podman run --rm sandbox:latest pi --version`; `podman run --rm sandbox:latest pi --list-skills` (equivalent probe); `bin/implementer-run.sh --task <sample-slug> --dry-run`; `podman kill <run-container>` mid-run then observe respawn; `bin/implementer-run.sh --task extension-inline-agent`.

Done = stage 2 completes: real PR raised from the sandbox with the full durable-trail artifacts in place, user inspected stage 1's dry run and discarded the sample.

## Out-of-scope

- **PR review / test / merge pipeline** (the post-PR gates: reviewer agent, CI, merge to main, post-merge test, production rollout) — explicitly deferred; the implementer terminates at "PR raised".
- **Cloud runtime deployment** — the image + profile make the worker cloud-ready, but actual provisioning (k8s/ECS job, durable volumes, scheduling) is the workspace cloud-migration task. Only the artifacts are produced here.
- **Multi-repo PRDs and concurrent implementers** — one PRD = one primary target repo; parallelism across repos is a later extension (the decoupled shape supports it).
- **`herdr-agent-state` and `subagent` extensions in the sandbox** — herdr deferred to the monitoring task; the implementer is a leaf worker with no children.
- **`web-search` in the sandbox** — scope discipline; the PRD is the contract.
- **Editing/regenerating pushed work** — the sandbox does not amend pushed branches after a run.

## Further notes

- `opensource/ponytail` updated to upstream `2ed6c52` (Grok Build adapter commit) and remains registered in the portability manifest (`opensource/ponytail`) — the always-on directive's source of truth.
- Local runs need no clone (bind mounts); the portability "smallest restoration" guarantee becomes the **cloud worker's** provisioning contract via the `factory-sandbox` profile (repos-only: workspace root + target repo + portability tooling; no snapshots/models/services).
- Context-window horizon: large PRDs may exceed one implementer context; v1 relies on commit-early + compaction, and the respawn/resume shape naturally extends to a **chain** (one fresh container per story group, passing briefs + handoff notes) — noted, not built.
- DB writes: none — the data model is files + git. `docs/implementations/` and `~/.factory/runs/` are the new durable stores.

## Architecture

### System diagram

```
HOST (durable — the harness)                                     CONTAINER (cattle — the hands)
─────────────────────────────────────────────────────────────      ──────────────────────────────────────────────
~/.factory/runs/<slug>-<ts>/                                      image: sandbox:<tag>  (built via workspace-portability)
  brief.md            ← driver writes                             ├─ node + pi (npm global) + git + python + gh CLI
  worktree/           ← git worktree of target repo (host disk)   ├─ portability tooling + factory-sandbox profile
  outbox/             ← implementer outputs (report, decisions)   ├─ ~/.pi/agent: settings.json (defaultProjectTrust=always),
  session.jsonl       ← driver-streamed implementer events           models/base config
  ├─ (mounted rw at /sandbox)                                  └─ run: pi --mode json --no-session -p \
docs/implementations/<date>-<slug>/                                --append-system-prompt <brief> [--model ...]
  report.md, decisions/*.md   ← driver-archived after run              cwd=/workspace   (skills/extensions discovered)
workspace root (host repos)                                        mounts:
  docs/prd-queue, docs/tasks, bin, .pi/, .agents/skills/             /workspace ← host workspace (READ-ONLY)
  └─ (mounted ro at /workspace)                                      /sandbox   ← run dir (read-write)
env (driver → container): LLM keys, LANGFUSE_* ONLY               env: NO GitHub token, NO host secrets
```

### Data flow (one run)

1. Operator: `bin/implementer-run.sh [--task <slug>|--pick] [--dry-run]`.
2. Driver: scan `docs/prd-queue/*.md` → select one `**Status**: Final` (oldest; skip tasks already `in-progress`).
3. Driver: resolve repo — task file `**Project**` → path in the portability manifest (root/software-factory → `.`).
4. Driver: create run dir + host-side worktree (`git worktree add ... -b factory/<slug>/<ts>` from the repo's manifest branch), write `brief.md` (PRD, task file, linked decisions, impl session UUID, worktree path, rules, verification commands, outbox paths).
5. Driver: `bin/transition-task.sh <slug> --to in-progress` and push the workspace root (implementation active).
6. Driver: `podman run --rm` the sandbox image (mounts + env + net=host for Langfuse/local stack) — the implementer pi runs inside; driver streams container stdout lines → `session.jsonl` **live**; liveness watch (timeout + heartbeat).
7. Implementer: read brief + PRD (ro), implement in worktree (rw), commit-early per story, run PRD verification commands, write `outbox/report.md` + `outbox/decisions/*.md`, exit.
8. Abnormal container death: driver respawns (≤ N=3) with same run dir/brief → implementer resumes from committed worktree state.
9. Success: driver archives report+decisions → `docs/implementations/<date>-<slug>/`; appends index entries (sort-knowledge-index.py); links impl session on task file; commits+pushes workspace root; pushes worktree branch; `gh pr create --base <manifest-branch>` (skipped on `--dry-run`).
10. Failure: driver writes partial report, transitions task back to `prd-ready`, exits non-zero. No PR.

### Interfaces / contracts

- **Brief** (`brief.md`, both mounted-at `/workspace/../brief` context and passed via `--append-system-prompt`): PRD path, task slug, worktree path, impl session UUID, hard rules, verification commands, outbox paths.
- **Implementer stdout protocol**: pi JSONL events (`message_end`, `tool_result_end`) — the driver's session-log input.
- **Outbox contract** (implementer → driver): `report.md` (per-story done/not-done + evidence, verification results, UAT hand-off list, decisions-emerged) + `decisions/NN-<slug>.md` (structured decision format; driver-appended index).
- **Driver config** (`config/implementer.json`): repo map, default model, timeouts/respawn cap, env allowlist, image tag, mount layout.
- **Portability contract**: new profile `factory-sandbox.conf` (repos-only), pi install setup step, `container/Dockerfile` + entrypoint + host wrapper `podman run`.

### Data model changes

- New trees: `~/.factory/runs/<slug>-<ts>/` (per-run, disposable after archive), `docs/implementations/<date>-<slug>/` (durable, committed).
- New task lifecycle edge: `prd-ready → in-progress` at pickup; remains `in-progress` until PR merge.
- Knowledge base: implementation sessions (`docs/knowledge/sessions/<impl-uuid>/`) with driver-captured `session.jsonl` + decisions; index entries appended by the driver only.
- `workspace_restore_manifest.json`: new profile + setup step (pi); repos already cover workspace root + all targets + `opensource/ponytail`.

## Program Design

### File-tree diff

**Workspace root (`ak47-arch/workspace.git`, branch `master`):**

```
bin/implementer-run.sh            (NEW) host driver: pick/scan, repo resolve, worktree+brief,
                                      podman run + live stream capture, respawn, archive,
                                      transition, push, gh pr create
bin/sandbox-build.sh              (NEW) podman build wrapper (image tag, context)
config/implementer.json           (NEW) driver config: repo map, model, timeouts, env allowlist
.pi/agents/implementer.md         (NEW) implementer agent definition (system prompt =
                                      ponytail directive + factory-worker rules + run contract refs)
.agents/skills/implementer-ops/SKILL.md      (NEW) run contract skill
.agents/skills/implementer-save/SKILL.md     (NEW) scoped decision capture (explicit session dir;
                                      index append is driver-only)
docs/implementations/.gitkeep     (NEW) durable run-report archive tree
docs/factory-context.md           (UPD) assembly_line component: implementer + sandbox
openwiki/projects/software-factory.md (UPD) implementer/sandbox section
openwiki/reference/agent-config.md      (UPD) implementer.md + implementer-ops + sandbox
bin/test-implementer-driver.sh    (NEW) fixture-based unit tests (temp queue, no git needed)
```

**workspace-portability (`ak47-arch/workspace-portability.git`, branch `main`):**

```
container/Dockerfile              (NEW) sandbox image: node base, deps, pi global install,
                                      portability tooling, ~/.pi/agent base config
                                      (defaultProjectTrust=always), entrypoint
container/sandbox-entrypoint.sh  (NEW) container boot: mount sanity, env sanity, exec implementer
container/run-sandbox.sh         (NEW) host wrapper: podman run --rm + mounts + env-file
profiles/factory-sandbox.conf    (NEW) profile: repos minimal, RESTORE_CRITICAL=false,
                                      HYDRATE_ASSETS=false, MATERIALIZE_SECRETS=false,
                                      START_SERVICES=false, RUN_SETUP=minimal
setup_pi.py                      (NEW) pi install + base config setup step (mirrors setup_workspace.py)
workspace_restore_manifest.json  (UPD) register profile deps + pi setup step
docs/PORTABILITY_PLAN.md, openwiki/ (UPD) pi installation no longer deferred; sandbox profile
```

### Call-stack trees

Driver (`bin/implementer-run.sh`):

```
implementer-run.sh [--task <slug>|--pick] [--dry-run]
  → resolve_prd()                       # grep '**Status**: Final' docs/prd-queue/*.md, oldest first
  → resolve_repo(slug, config)          # task Project → manifest repo path (root for software-factory)
  → prepare_run_dir(run_root)           # mkdir worktree/ outbox/, write brief.md
  → git -C <repo> worktree add <run>/worktree -b factory/<slug>/<ts> <manifest-branch>
  → transition prd-ready → in-progress  # bin/transition-task.sh + push workspace root
  → podman run ... sandbox:<tag>        # mounts: /workspace ro, /sandbox rw; env allowlist; net host
      └─ capture stdout (live append → session.jsonl); liveness watch
         → abnormal death → respawn ≤ N
  → on success: archive outbox → docs/implementations/<date>-<slug>/
      → index append (sort-knowledge-index.py) → task-file session link
      → commit+push workspace root
      → git push <repo> factory/<slug>/<ts>
      → gh pr create --base <manifest-branch> --title/body from brief+report  (skip on --dry-run)
  → on failure: partial report, transition back to prd-ready, exit 1
```

Implementer (inside container, headless pi):

```
pi --mode json --no-session -p --append-system-prompt <brief.md> [--model $IMPLEMENTER_MODEL]
  cwd=/workspace → reads brief + PRD (ro mount)
  per story: edit worktree (rw) → verify (PRD commands) → git commit  (commit-early)
  finish: write outbox/report.md + outbox/decisions/*.md → exit 0 (or exit 1 with partial report)
```

### Key types and signatures

```bash
# driver
implementer-run.sh --pick | --task <slug> [--dry-run] [--resume]   # exit 0 = PR raised / dry-run done
# config
{
  "repo_map": { "feed_analyser": "feed_analyser", "software-factory": ".", ... },
  "model": "openrouter/deepseek/deepseek-v4-flash-0731",
  "timeout_sec": 1800, "respawn_cap": 3,
  "env_allowlist": ["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "LANGFUSE_*", "IMPLEMENTER_MODEL"],
  "image": "sandbox:<tag>"
}
# brief.md (contract)
#   PRD path · task slug · worktree path · impl session UUID · rules (no docs writes,
#   no secrets, commit-early) · PRD verification commands · outbox paths
# outbox/report.md (contract)
#   per-story done/not-done + evidence · verification results · UAT hand-off · decisions-emerged
# podman run (signature)
podman run --rm --network=host \
  -v <host-workspace>:/workspace:ro \
  -v <run-dir>:/sandbox \
  --env-file <secrets.env-filtered> \
  sandbox:<tag> pi --mode json --no-session -p --append-system-prompt /sandbox/brief.md
```

### Build / run notes

- Build: `bin/sandbox-build.sh` → `podman build -t sandbox:<tag> workspace-portability/container/` (secrets never baked; repo clone happens at run time only on cloud workers).
- Local run: `bin/implementer-run.sh --pick` (dry-run: `--dry-run`).
- Resilience: `podman kill <container>` during a run must leave worktree/session intact and respawn and resume.
- Langfuse: `--network=host` (rootless podman) reaches the local Langfuse stack; cloud later uses its service endpoint via `LANGFUSE_BASE_URL`.
- Cloud worker: the `factory-sandbox` profile bootstraps the durable workspace (root + target repos) then runs the identical driver.