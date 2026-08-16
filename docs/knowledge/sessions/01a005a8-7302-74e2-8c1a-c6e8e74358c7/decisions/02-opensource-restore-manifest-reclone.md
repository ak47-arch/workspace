## Decision: opensource/ disaster recovery via manifest re-clone — stale fork URLs fall back to upstream

**Status**: accepted
**Date**: 2026-08-16 23:20
**Task**: ponytail-skills-fixed-mount
**Project**: software-factory
**Session**: sessions/01a005a8-7302-74e2-8c1a-c6e8e74358c7/session.jsonl

### Context

The `opensource/` directory (26 repos) was silently deleted on 2026-08-15 by a host-side git op (see decision 01 — the D2 path-coupling failure chain). Recovery was needed before the fix could be verified end-to-end. The restore tooling in `workspace-portability/` (`restore-workspace.sh` → `restore_workspace.py`, driven by `workspace_restore_manifest.json`) is designed for full-workspace restore from git remotes + the critical snapshot — not for a targeted single-directory recovery into a live workspace.

### Problem

How to restore only `opensource/` into the live workspace without touching anything else, and what to do when a recorded clone URL no longer exists (the manifest is a backup record and can go stale).

### Alternatives

1. **Full `restore-workspace.sh` run (with snapshot)** — rejected: extracts snapshot `restore_paths` including `survival-infrastructure/` data paths into the live workspace, risking clobber of current data.
2. **Targeted re-clone via manifest** (`--no-snapshot --repos <opensource-paths>`) — chosen: idempotent (skips existing repos), parallel (4 workers), restores only the opensource repos into the existing git repo.
3. **Manual `git clone` per repo** — rejected: loses the manifest as the single source of truth, no parallel worker pool, no remote-config normalization.

### Decision

1. Re-clone opensource repos with `restore-workspace.sh "$PWD" --no-snapshot --repos "$(opensource paths)"` — the script clones into the live workspace (it accepts an existing git repo as destination), is idempotent on re-run, and leaves all non-opensource paths untouched.
2. Extract snapshot-only runtime data separately: `opensource/hermes/.hermes-data` came from the Aug 13 critical snapshot via `tar -xzf ... --strip-components=3 workspace-critical-snapshot/opensource/hermes/.hermes-data` (it is not in git).
3. **Stale fork fallback**: when a manifest clone URL 404s (`ak47-arch/skills.git` — fork deleted upstream), use the manifest entry's `extra_remotes.upstream` URL instead (`mattpocock/skills.git`), and flag the manifest entry as stale. The `ensure_repo()` failure output is explicit enough to spot these; the script's exit is a SystemExit listing failed repos, so a per-repo failure aborts the whole restore — acceptable, fix the URL and re-run (idempotent).

### Rationale

- The manifest is the single source of truth for what `opensource/` contains; re-cloning from it guarantees structural fidelity (repo names, remotes, branches) without hand-maintained clone lists.
- `--no-snapshot` isolates the recovery to repos — the critical snapshot is only useful for `opensource/hermes/.hermes-data` (and `survival-infrastructure`), which we extract selectively.
- Idempotency means a failed repo (404, network) can be repaired and the restore re-run safely.

### Consequences

- `opensource/` restored 26/26; six ponytail skills available at `opensource/ponytail/skills/`; `opensource/` remains untracked (bare `opensource` gitignore pattern) so re-restores are safe.
- **Stale manifest entry discovered**: `ak47-arch/skills.git` returns 404 (fork deleted upstream); `opensource/skills` was cloned from upstream `mattpocock/skills.git`. The manifest still lists the dead fork URL — a follow-on task should update `workspace_restore_manifest.json` (and restore-path checks) to the upstream URL.
- The D2 fix was then verified end-to-end (implement → review → merge → post-merge checkout) with **no replication** of the deletion bug.

### Revision triggers

- The `ak47-arch/skills.git` manifest entry is corrected (or the fork is restored) — decision's fallback note becomes stale.
- Manifest gains a first-class "fallback clone URLs" concept (would supersede the manual upstream-fallback step).
- Restore tooling grows a `--repos-only-into-existing` guard or a per-directory restore mode (would formalize what was done ad hoc here).
