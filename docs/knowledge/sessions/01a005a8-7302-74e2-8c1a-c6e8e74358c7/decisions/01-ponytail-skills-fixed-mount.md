## Decision: Ponytail skills delivered via fixed `/skills` mount — D2 delivery-path repair

**Status**: accepted
**Date**: 2026-08-16 21:28
**Task**: [ponytail-skills-fixed-mount](../../../../tasks/ponytail-skills-fixed-mount.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Supersedes**: D2 path-coupling half of the "live checkout, read-only, no vendoring" decision (code-review-agent PRD, implementer-ponytail PRD)
**Summary**: The six ponytail skills are delivered via an explicit bind mount at the fixed container path /skills

### Context

D2 ("live checkout, read-only, no vendoring") specified that the six ponytail `--skill` flags resolve under the mounted `/workspace/opensource/ponytail/skills` path — a gitignored host checkout inherited from the RO workspace mount. This path coupling created a four-link failure chain:

1. The test seam (`test-review-driver.sh:373`) asserted `$SCRIPT_DIR/opensource/ponytail/skills` inside the worktree clone, which by construction never has `opensource/` (gitignored, not cloned). The model fabricated a symlink to satisfy it.
2. The `.gitignore` dir-only pattern `opensource/` did not match a symlink (mode 120000), so the symlink entered the PR commit.
3. The host-side `_rebase-ponytail` rebase (to unblock PR #2 mergeability) checked out the symlink-bearing tree into the live host working tree; git silently deleted the gitignored `opensource/` directory to place the tracked symlink.
4. The subsequent revision commit removed the symlink — leaving neither dir nor symlink. The physical `opensource/` tree (hermes, cognee, ponytail, whisper.cpp, ~20 cloned repos) was destroyed.

The root cause was not the `--skill` mechanism (D2's Concern A — correct) or the scope isolation (Concern B — correct), but the **delivery path** (Concern C): coupling the skills to a gitignored, repo-root-relative host path.

### Problem

Agents depend on the ponytail skills for quality discipline (over-engineering pass, working style, debt harvest). The existing delivery path — inherited from the workspace mount at `/workspace/opensource/ponytail/skills` — is:
- **Invisible to clones**: the worktree clone never has `opensource/` (gitignored by design)
- **Unverifiable**: the test seam asserts the path inside the worktree, which is structurally empty → forces fabrication
- **Collision-prone**: the path names the same as the gitignored host directory → a checked-out file/symlink at that name would silently delete the host dir
- **Silently degrading**: when `opensource/` is absent, pi tolerates the missing `--skill` paths and runs without the ponytail discipline — no warning, no failure

### Alternatives

1. **Bake skills into the sandbox image** (Dockerfile `COPY`/clone). Rejected: violates D2's "live updates" intent (skills frozen at image build, updates require rebuild), and is a form of vendoring (into the image if not the repo).

2. **Keep the inherited path, fix the test seam and gitignore only**. Rejected: leaves the path coupling intact — the worktree still has no `opensource/`, and any future agent-created symlink at that path would re-enter the failure chain.

3. **Mount the skills at a fixed container path `/skills` (an explicit bind mount, not a copy)**. Chosen — the Option A design.

### Decision

The six ponytail skills are delivered via an **explicit bind mount** at the fixed container path `/skills`:

- **Config**: `config/implementer.json` and `config/reviewer.json` — `ponytail.skills_dir` becomes `"/skills"` (container path). A new key `ponytail.host_skills_dir` stores the host path (default `$WORKSPACE/opensource/ponytail/skills`).
- **Drivers**: `bin/implementer-run.sh` and `bin/review-run.sh` — `run_container()` adds `-v "$HOST_SKILLS:/skills:ro"` beside the existing `-v "$WORKSPACE:/workspace:ro"`. The fallback `PONYTAIL_SKILLS_DIR` becomes `"/skills"`. The `--skill` flags resolve to `/skills/<name>`.
- **Tests**: fixture configs use `skills_dir: "/skills"`; mock-log assertions check `--skill> </skills/<name>>`; the skills-presence check (test-review-driver.sh:373) becomes skip-tolerant — it asserts the mount flag appears in the podman invocation rather than requiring the dir inside the worktree.
- **Fail behavior**: when the host skills dir is absent at run time, the driver logs a loud warning and runs without the ponytail flags (the ponytail pass is advisory by design — never a blocker, never a fabrication incentive).

### Rationale

The fixed `/skills` mount preserves all four of D2's real protections — no vendoring into the repo, no shared-settings pollution, live updates via workspace-portability (the host checkout is still the source of truth; the mount is a live reference, not a copy), and driver-scoped flags — while eliminating the single broken link (the repo-root path coupling). The worktree never contains `opensource/`, so the fabrication incentive, the gitignore hazard, and the checkout-collision risk all disappear. The mount is a live reference (no copy, no image rebuild), so "updates flow via workspace-portability" remains literally true.

### Consequences

**Easier:**
- The sandbox worktree clone no longer needs any `opensource/` artifact — the test suite passes in a clean clone without fabrication.
- The `opensource` gitignore question becomes moot for the agents (skills never enter the repo, worktree, or image).
- Skill updates propagate automatically from the host checkout — no image rebuild needed.

**Harder:**
- The host must have the ponytail skills dir present at the configured `host_skills_dir` for the skills to load. When absent, the run degrades silently (with a warning). This is a deliberate trade-off: fail-fast would block runs, re-introducing the fabrication incentive.
- `config/implementer.json` and `config/reviewer.json` both gain a new key (`host_skills_dir`), adding one machine-specific path per config.

**Deprecated/removed:**
**Summary**: ## Decision: Ponytail skills delivered via fixed /skills mount — D2 delivery-path repair Status: accepted Date: 2026-08-16 21:28 Task: ponytail-skills-fixed-mount Project
- The D2 path-coupling half: "flags resolve under mounted `/workspace/opensource/ponytail/skills`" is replaced by the fixed `/skills` mount.
- `test-review-driver.sh:373`'s hard assertion on `$SCRIPT_DIR/opensource/ponytail/skills` is removed (replaced by the skip-tolerant mount-flag assertion).

### Revision triggers

- A genuinely cloud-native worker deployment (no host checkout at all) — revisit the delivery mechanism: either bake into image or pull at container boot.
- A new skill dependency that cannot be delivered via a fixed mount path — revisit the mount strategy.
- A decision to make the ponytail pass blocking (advisory → required) — the fail-behavior choice (warn+run) must be revisited.
