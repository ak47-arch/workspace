## Decision: Repo-key resolution semantics for the PRD **Repos:** header

**Status**: accepted
**Date**: 2026-08-18
**Task**: [multi-repo-delivery-bookkeeping-prs](../../../../tasks/multi-repo-delivery-bookkeeping-prs.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Accepted: dual-key lookup with workspace = root.

### Context
The multi-repo delivery PRD lets a PRD declare `**Repos:** workspace, feed_analyser`. The driver must resolve each declared name to a checkout/branch to deliver code and bookkeeping PRs, and it must enforce the delivery invariant (root-code PR vs bookkeeping PR are exclusive).

### Problem
There is no canonical repo namespace in `config/implementer.json`: the `repo_map` is keyed by checkout path (e.g. `.` for the root) with a `repo:` field holding the GitHub `<owner>/<repo>` string. `**Repos:** workspace, feed_analyser` uses *repo short names*, not paths and not `<owner>/<repo>`. The resolver must map a PRD name to a predictable branch key.

### Alternatives
1. Treat `**Repos:**` entries as `repo_map` *values* only (`<owner>/<repo>`), rejecting short names.
2. Treat entries as `repo_map` *keys* (checkout paths) only.
3. **Adopt a dual-key lookup** that accepts either the short org/repo name **or** the value `repo:` string, canonicalizing at the repo_map value's directory; `workspace` (and the rootless layout) maps to the root repo key `workspace`.

### Decision
**Accepted: dual-key lookup with `workspace` = root.** For each token in `**Repos:**`, resolve it to a canonical repo key:
**Summary**: ## Decision: Repo-key resolution semantics for the PRD Repos: header Status: accepted Date: 2026-08-18 Task: multi-repo-delivery-bookkeeping-prs Project: software-factory
- `workspace` (or a token matching the root) → repo key `workspace`, marking `ROOT_IN_SET=true`, with the root checkout at `$WORKSPACE`.
- otherwise, match the token against each `repo_map` entry's `repo:` value **OR** its short name suffix; the canonical key is the repo's directory name merged into `REPO_KEYS` (de-duplicated).
- record per-repo `REPO_MANIFEST_BRANCH[key]` from the entry's `manifest_branch` / `branch` (for `feed_analyser` → `public-release`).
- any unresolved token → die(exit 2) with the unavailable name, telling the operator to add it to `config/implementer.json` or remove it from the PRD.

Delivery shape selected by `ROOT_IN_SET` + whether `workspace` is the only key: Shape A single-app code PR + bookkeeping PR; Shape B root-code+bookkeeping single PR; elif hybrid → root fast-track plus N-1 app PRs, then the single bookkeeping PR. The invariant `assert_delivery_invariant` enforces root-code-PR ⇔ bookkeeping-PR exclusivity, which pins the *branch-key bookkeeping* interpretation: the git truth is owned by the root repo's `factory-pr` row, branch keys are cosmetic.

### Rationale
Accepts both existing PRD conventions and the `repo_map` value `repo:` strings without requiring a new config schema; keeps `workspace` as the stable root key so factory-run/merge-pr can address it unconditionally.

### Consequences
- `REPO_KEYS`, `ROOT_IN_SET`, `REPO_MANIFEST_BRANCH` are global in `implementer-run.sh`; `deliver_repo_set` iterates `REPO_KEYS`, delegating the root to `deliver_shape_b_root` (Shape B) and app repos to per-checkout `deliver_repo`.
- The run manifest keys by repo-key with `{branch, pr, verdict, state}`.
- Unknown/legacy checkouts are surfaced as die(exit 2) rather than silently downgraded.

### Revision triggers
A PRD that legitimately needs a repo not present in `config/implementer.json`'s repo_map (add it or drop the header entry). A future schema that introduces a true repo-namespace field would simplify the dual-key lookup.
