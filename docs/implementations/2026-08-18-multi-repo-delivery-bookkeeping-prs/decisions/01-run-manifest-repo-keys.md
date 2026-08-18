## Decision: Run-manifest repo keys are canonical repo_map keys (not GitHub repo names)

**Status**: accepted
**Date**: 2026-08-18 17:30
**Task**: multi-repo-delivery-bookkeeping-prs
**Project**: software-factory
**Session**: sessions/c63649d5-f660-4494-af41-d0025d02f728/session.jsonl

### Context
The PRD's run-manifest schema sample shows `repos` keys like `goal-agent` and
`llamacpp_inference_server` — the GitHub *repo names* — while branch naming is
specified as `factory/<slug>/<repo-key>/<ts>` with repo-key = the repo_map value
dir (`workspace` for root). The PRD also notes "real keys come from the current
config/implementer.json repo_map", which uses different local dir names
(`survival-infrastructure`, `llm`).

### Problem
Which identifier is the canonical `repos` key in the manifest (and thus the join
across manifest, branch names, and per-repo PR tracking)?

### Alternatives
- Use GitHub repo names (`goal-agent`, `llamacpp_inference_server`).
- Use the repo_map value dir (`survival-infrastructure`, `llm`), with `.` → `workspace`.

### Decision
Use the **canonical repo key** = repo_map value dir, with `.`/`workspace` for the
root. This is the same key used in `factory/<slug>/<repo-key>/<ts>` branch naming,
so the manifest's `repos` object keys, the branch names, and the per-repo PR
tracking all share one identifier.

### Rationale
- Single identifier across manifest, branches, and tracking — no translation layer
  (local dir ↔ GitHub name) required at read time.
- Matches the branch-naming spec exactly; the PRD's sample keys are explicitly
  illustrative and conflict with its own "real keys come from repo_map" note.
- The GitHub-name mapping already lives in the CI `REPO_NAME` associative array;
  keeping it out of the manifest avoids duplicating that knowledge.

### Consequences
- `write_run_manifest` emits `workspace`, `feed_analyser`, `llm`,
  `survival-infrastructure`, etc. as `repos` keys.
- `factory-run.sh resolve_pr_set_from_manifest` iterates those keys to build the
  code-PR set (each `pr` resolved against the default repo).
- No code depends on GitHub-name keys.

### Revision triggers
- If a future requirement wants a single manifest shared verbatim with a tool that
  understands GitHub repo names only.
