## Decision: Parallel Repo Clone

**Status**: accepted
**Date**: 2026-07-24 17:07
**Project**: workspace-portability
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Replace the sequential for repo in repos: loop with concurrent.futures.ThreadPoolExecutor(max_workers=4).

### Context

Workspace portability's `restore_workspace.py` clones all repos sequentially. With 29 repos in the manifest, a full restore takes 5-10 minutes on a typical connection. The sequential loop was fine when the manifest had ~10 repos, but as more open-source projects were added the restore time grew proportionally.

### Problem

Sequential cloning of 29 repos is slow and wastes bandwidth on idle connections. Each repo clone spends most of its time waiting on network I/O, but the script didn't overlap those waits.

### Alternatives

1. **Sequential (status quo)** — keep the `for repo in repos:` loop. No throughput improvement, no complexity.
2. **`ThreadPoolExecutor` with max_workers=4** — chosen. Small code change (~15 lines), overlaps network I/O, safe concurrency for subprocess-based git operations.
3. **`asyncio` with `asyncio.create_subprocess_exec`** — more complex, native async, but the script is already sync and has no async infrastructure. Overkill for this use case.
4. **`multiprocessing.Pool`** — heavier, each worker is a separate process. No benefit over threads for subprocess I/O.
5. **Background the whole restore with `nohup`** — doesn't speed up individual clones, just lets the user walk away.

### Decision

Replace the sequential `for repo in repos:` loop with `concurrent.futures.ThreadPoolExecutor(max_workers=4)`. Each repo is cloned in its own thread; `ensure_repo` delegates to `subprocess.run` which releases the GIL, so 4 concurrent git processes run without Python contention.

Output interleaving is handled with a `threading.Lock` around the success/failure prints (the `✓`/`✗` lines). Internal prints from `ensure_repo` are unprotected — they may interleave but carry directory prefixes (`[path]`), so the output remains parseable. Errors from any repo are collected and reported as a batch after all workers finish.

### Rationale

- Smallest change for largest gain — 4 workers yields ~4x throughput on network-bound cloning without hitting GitHub secondary rate limits.
- `ThreadPoolExecutor` is stdlib, no new dependencies.
- Existing retry logic for DNS/network failures is preserved inside each worker.
- Subprocess-based git operations are thread-safe (each thread spawns its own child process).
- No file conflicts between repos (each clones to a unique `dest/repo['path']`).

### Consequences

- Restore time for 29 repos drops from ~8min to ~2-3min on a typical connection.
- Output lines from different repos may interleave during clone, but each line is prefixed with the repo path.
- A single repo failure no longer aborts the entire restore immediately — all other clones complete, then all errors are reported together.
- `--repos` argument is unaffected; the group resolution (all/core/llm) happens before the parallel stage.

### Revision triggers

- GitHub secondary rate limiting becomes an issue (>4 concurrent clones from the same IP trigger 403s).
- A repo's `ensure_repo` logic becomes thread-unsafe (e.g., shared mutable state).
- The manifest grows to 50+ repos and 4 workers is no longer enough — add a `--jobs` flag instead of bumping the hardcoded value.
- A credential helper that doesn't survive threading is introduced.
