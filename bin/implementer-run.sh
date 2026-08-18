#!/usr/bin/env bash
# ============================================================================
# implementer-run.sh — Host-side driver for the sandboxed implementer agent.
#
# The implementer follows a decoupled brain/hands pattern:
#   * HOST (this driver): deterministic orchestration + ALL git mutations.
#     Picks a `**Status**: Final` PRD, creates a durable host-side worktree,
#     writes a task brief, provisions the sandbox container (cattle) with
#     read-only workspace + read-write run dir, streams the implementer's
#     JSONL event output live into a host-side session log, watches liveness,
#     respawns on abnormal container death, and on success archives the run
#     report + decisions, pushes the worktree branch, and raises a PR. After
#     delivery the container is shut down and the run dir is stripped of
#     disposable residue (installed deps, raw trace logs) so the host never
#     accretes ~300 MB of throwaway deps per task — durable artifacts (outbox,
#     session evidence, brief, worktree source) are always kept.
#   * CONTAINER (the hands): one headless `pi` process running the
#     implementer agent inside a podman sandbox image. Holds nothing durable;
#     all state exits through git / the run dir on the host.
#
# Usage:
#   bin/implementer-run.sh [--task <slug>|--pick] [--dry-run]
#   bin/implementer-run.sh --revise <pr> [--dry-run]
#   --task <slug>   Run a specific Final PRD (default: --pick)
#   --pick          Select the oldest Final PRD not already in-progress
#   --revise <pr>   Revision mode (decision 08): resume the ORIGINAL impl session
#                   (same --session-id/--continue, same branch) to address the
#                   review findings on an open PR. Resolves PR → slug → original
#                   impl session UUID → newest REQUEST_CHANGES review, seeds the
#                   run dir with the original session + mounts the review report
#                   as binding authority, then delivers by pushing the SAME
#                   branch (no new PR, no merge, no task transition).
#   --dry-run       Produce worktree + brief + session log, but NO push, NO PR,
#                   NO workspace-root commit. State transitions are simulated.
#                   In revise mode, dry-run stops after reconstructing the run dir
#                   and simulating the pi invocation.
#   --resume        (reserved) Resume an interrupted run from its run dir.
#
# Exit codes:
#   0  Success (PR raised / revision delivered, or dry-run completed)
#   1  Failure (partial report written, task reverted to prd-ready / revision
#      undelivered, no PR)
#   2  Usage / selection / resolution error (no Final PRD, invalid slug, closed
#      or merged PR in revise mode, unresolved review, etc.)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test seam: IMPLEMENTER_WORKSPACE lets fixture-based tests point the driver
# at a disposable workspace without any real git context.
WORKSPACE="${IMPLEMENTER_WORKSPACE:-$SCRIPT_DIR}"
CONFIG_FILE="$WORKSPACE/config/implementer.json"

# ─── Config loading ────────────────────────────────────────────────────────
# Pull scalar values from config/implementer.json with jq; fall back to a
# here-doc default if jq is unavailable (all values mirrored).
if command -v jq >/dev/null 2>&1; then
  cfg() { jq -r "$1" "$CONFIG_FILE"; }
  MODEL="$(cfg '.model')"
  TIMEOUT_SEC="$(cfg '.timeout_sec')"
  RESPAWN_CAP="$(cfg '.respawn_cap')"
  IMAGE="$(cfg '.image')"
  RUNS_ROOT="$(cfg '.runs_root')"
  ARCHIVES_ROOT="$(cfg '.archives_root')"
  LIVENESS_INTERVAL="$(cfg '.liveness_interval_sec')"
  LIVENESS_IDLE="$(cfg '.liveness_idle_sec')"
  CLEANUP_ENABLED="$(cfg '.cleanup_enabled // true')"
  KEEP_WORKTREE="$(cfg '.keep_worktree // true')"
  PONYTAIL_SKILLS_DIR="$(cfg '.ponytail.skills_dir')"
  PONYTAIL_DEFAULT_MODE="$(cfg '.ponytail.default_mode')"
  HOST_SKILLS="$(cfg '.ponytail.host_skills_dir')"
  HOST_SKILLS="${HOST_SKILLS//\$WORKSPACE/$WORKSPACE}"
  HOST_SKILLS="${HOST_SKILLS//\$\{WORKSPACE\}/$WORKSPACE}"
  repo_map_path() { cfg ".repo_map[\"$1\"] // empty"; }
  env_allowed() { jq -r '.env_allowlist[]' "$CONFIG_FILE"; }
else
  MODEL="openrouter/deepseek/deepseek-v4-flash-0731"
  TIMEOUT_SEC=1800
  RESPAWN_CAP=3
  IMAGE="sandbox:latest"
  RUNS_ROOT="$HOME/.factory/runs"
  ARCHIVES_ROOT="docs/implementations"
  LIVENESS_INTERVAL=15
  LIVENESS_IDLE=300
  CLEANUP_ENABLED=true
  KEEP_WORKTREE=true
  PONYTAIL_SKILLS_DIR="/skills"
  PONYTAIL_DEFAULT_MODE="ultra"
  HOST_SKILLS="$WORKSPACE/opensource/ponytail/skills"
  repo_map_path() {
    case "$1" in
      software-factory|langfuse) echo "." ;;
      feed_analyser) echo "feed_analyser" ;;
      workspace-portability) echo "workspace-portability" ;;
      survival-infrastructure) echo "survival-infrastructure" ;;
      llm) echo "llm" ;;
      headroom-pi) echo "headroom-pi" ;;
      resume) echo "resume" ;;
      emotional_architecture) echo "emotional_architecture" ;;
      *) echo "" ;;
    esac
  }
  env_allowed() { printf '%s\n' OPENROUTER_API_KEY ANTHROPIC_API_KEY \
    LANGFUSE_SECRET_KEY LANGFUSE_PUBLIC_KEY LANGFUSE_BASE_URL \
    IMPLEMENTER_MODEL PONYTAIL_DEFAULT_MODE; }
fi

RUNS_ROOT="${RUNS_ROOT/#\~/$HOME}"
# Test seams: allow fixture-based tests to point the run root / archive root at
# a disposable workspace (like IMPLEMENTER_WORKSPACE) without touching real home.
RUNS_ROOT="${IMPLEMENTER_RUNS_ROOT:-$RUNS_ROOT}"
ARCHIVES_ROOT="${IMPLEMENTER_ARCHIVES_ROOT:-$ARCHIVES_ROOT}"

# ─── Helpers ───────────────────────────────────────────────────────────────
now_ts() { date '+%Y%m%d-%H%M%S'; }
now_human() { date '+%Y-%m-%d %H:%M'; }
new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}

die() { echo "ERROR: $*" >&2; exit 2; }

# Active gh / podman binaries (test seams: point IMPLEMENTER_GH_BIN /
# IMPLEMENTER_PODMAN_BIN at mocks so the driver's `main` can execute without a
# real GitHub / container runtime). Resolved at call time.
gh_call() { "${IMPLEMENTER_GH_BIN:-gh}" "$@"; }

# Active podman binary (test seam: point IMPLEMENTER_PODMAN_BIN at a mocked
# podman so the driver's `main` can be executed end-to-end without a real
# container runtime). Resolved at call time so a fixture can set it after the
# driver is sourced.
podman_call() { "${IMPLEMENTER_PODMAN_BIN:-podman}" "$@"; }

# Task slug from a PRD filename: yyyy-mm-dd-<slug>.md → <slug>
slug_from_prd() { basename "$1" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//'; }

# ─── Arg parsing ───────────────────────────────────────────────────────────
TASK=""
DRY_RUN=false
MODE_FLAG="--pick"
REVISE_PR=""
# Revision mode (decision 08): set true when --revise is active. Under revise,
# the container resumes the original session from attempt 1 (--continue), the
# revision directive carries the binding-authority rule, the task NEVER
# transitions (stays in-review), no new UUID is minted, and delivery pushes the
# same branch (no gh pr create, no merge).
REVISION_MODE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="$2"; MODE_FLAG=""; shift 2 ;;
    --pick) MODE_FLAG="--pick"; shift ;;
    --revise) REVISE_PR="$2"; MODE_FLAG=""; REVISION_MODE=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --resume) echo "WARN: --resume is reserved; not implemented in v1." >&2; shift ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ─── resolve_prd(): select one Final PRD ───────────────────────────────────
# ─── Multi-repo delivery state (PRD: multi-repo delivery bookkeeping PRs) ───
# Populated by resolve_repo_set / deliver_repo_* / factory-run.sh cooperatively.
REPO_KEYS=()
ROOT_IN_SET=false
BOOKKEEPING_PR=""
ROOT_CODE_PR=""
REVISIONS=0
SHAPE_OUTCOME="in-progress"
TRIPS_DOCS_ONLY=true
RUN_ID="$(now_ts)"
declare -gA REPO_BRANCH=()
declare -gA REPO_PR=()
declare -gA REPO_VERDICT=()
declare -gA REPO_STATE=()
declare -gA REPO_WORKTREE=()

# - $MODE_FLAG=--pick: oldest `**Status**: Final` in docs/prd-queue/ whose task
#   is `**Status**: prd-ready` (the lifecycle's queued-entry state — decision 09).
#   in-progress (concurrent owner) and in-review (merged/blocked/verifying
#   lineages) tasks are NOT pickable; a stale Final PRD for an in-flight or
#   merged task must never be re-implemented. Oldest = smallest date prefix in
#   filename.
# - --task: the PRD whose filename carries the given slug (explicit operator
#   override — NOT gated on task status).
resolve_prd() {
  local prd=""
  if [ -n "$MODE_FLAG" ]; then
    local candidate
    local best=""
    for candidate in "$WORKSPACE"/docs/prd-queue/*.md; do
      [ -f "$candidate" ] || continue
      grep -q '^\*\*Status\*\*: *Final' "$candidate" || continue
      local slug; slug="$(slug_from_prd "$candidate")"
      local task_file="$WORKSPACE/docs/tasks/$slug.md"
      if [ ! -f "$task_file" ] \
         || ! grep -q '^\*\*Status\*\*: *prd-ready' "$task_file" 2>/dev/null; then
        echo "  [pick] skipping $slug (task not prd-ready — in-flight/merged/unknown)" >&2
        continue
      fi
      [ -z "$best" ] && best="$candidate"
      # Filename date prefix sorts oldest-first; pick smallest.
      if [ "$(basename "$candidate")" \< "$(basename "$best")" ]; then
        best="$candidate"
      fi
    done
    prd="$best"
  else
    prd="$(ls "$WORKSPACE"/docs/prd-queue/*-"$TASK.md" 2>/dev/null | head -1 || true)"
  fi

  if [ -z "$prd" ] || [ ! -f "$prd" ]; then
    if [ -n "$MODE_FLAG" ]; then
      die "No pickable 'Final' + prd-ready PRD in docs/prd-queue/ (all in-flight, merged, or not queued)."
    fi
    die "No PRD found for slug '$TASK' in docs/prd-queue/"
  fi

  # Must be Final to be routeable.
  if ! grep -q '^\*\*Status\*\*: *Final' "$prd"; then
    die "PRD $prd is not 'Final' (not past the review gate)."
  fi

  echo "  Selected PRD: $(basename "$prd")" >&2
  PRD="$prd"
  PRD_SLUG="$(slug_from_prd "$prd")"
  if [ -n "$TASK" ]; then
    PRD_SLUG="$TASK"
  fi
}

# ─── resolve_repo(): task Project → repo path via repo_map ─────────────────
resolve_repo() {
  local task_file="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  [ -f "$task_file" ] || die "Task file not found: $task_file"
  PROJECT="$(grep -m1 '^\*\*Project\*\*:' "$task_file" | sed 's/^\*\*Project\*\*: *//')"
  if [ -z "$PROJECT" ]; then
    PROJECT="software-factory"
  fi
  TARGET_REPO="$(repo_map_path "$PROJECT")"
  if [ -z "$TARGET_REPO" ]; then
    # Unmapped project: default to workspace root.
    echo "  [warn] project '$PROJECT' not in repo_map; defaulting to workspace root." >&2
    TARGET_REPO="."
  fi
  echo "  Resolved project '$PROJECT' → repo '$TARGET_REPO'" >&2

  # Manifest branch for the target repo (via workspace-portability manifest).
  MANIFEST_BRANCH="$(python3 - "$TARGET_REPO" "$WORKSPACE" <<'PYEOF'
import json, sys, os
repo, workspace = sys.argv[1], sys.argv[2]
manifest = os.path.join(workspace, "workspace-portability", "workspace_restore_manifest.json")
try:
    with open(manifest) as f:
        data = json.load(f)
    for r in data.get("repos", []):
        if r.get("path") == repo:
            print(r.get("branch", "master"))
            sys.exit(0)
except Exception:
    pass
print("master")
PYEOF
  )"
  echo "  Target repo manifest branch: $MANIFEST_BRANCH" >&2
  # Multi-repo resolution (PRD: **Repos:** header). Populates REPO_KEYS,
  # ROOT_IN_SET, REPO_MANIFEST_BRANCH. The single-repo TARGET_REPO flow above
  # remains for backward compatibility.
  resolve_repo_set
}

# ═══════════════════════════════════════════════════════════════════════════
# Multi-repo delivery (PRD: multi-repo delivery bookkeeping PRs).
#
# A task's PRD declares a set of repos via the `**Repos:**` header (comma-
# separated repo_map values; `.`/`workspace` = root). The root is a repo like
# any other. Exactly two shapes, no third:
#   Shape A (root NOT touched): N app code PRs + 1 bookkeeping PR (docs-only)
#   Shape B (root touched):      N-1 app PRs + 1 root PR (code + bookkeeping
#                                commits on the SAME branch)
# Invariant (asserted every delivery):
#   (root code PR exists AND no bookkeeping PR) XOR (no root code PR AND one bk PR)
# ═══════════════════════════════════════════════════════════════════════════

# repo_map_has_value <dir>: 0 if <dir> is one of the repo_map VALUES (dir paths),
# 1 otherwise. Works in both the jq and no-jq (fallback) config paths.
repo_map_has_value() {
  local v="$1"
  if command -v jq >/dev/null 2>&1; then
    if jq -r --arg v "$v" '.repo_map | to_entries[] | select(.value == $v) | .value' "$CONFIG_FILE" 2>/dev/null | grep -qx "$v"; then
      return 0
    fi
    return 1
  fi
  case "$v" in
    .|feed_analyser|workspace-portability|survival-infrastructure|llm|headroom-pi|resume|emotional_architecture|timesheetViewer) return 0 ;;
    *) return 1 ;;
  esac
}

# repo_key_for <identifier>: canonical repo-map-value-dir key from a `**Repos:**`
# identifier. Accepts repo_map KEYS (project names) AND repo_map VALUES (dir
# paths). `.`/`workspace` = root → canonical key 'workspace'. Echoes '' (errors)
# when the identifier is neither a repo_map key nor a repo_map value.
repo_key_for() {
  local id="$1"
  case "$id" in
    .|workspace) echo "workspace"; return 0 ;;
  esac
  # repo_map key (project name) → value path.
  local v; v="$(repo_map_path "$id")"
  if [ -n "$v" ]; then
    case "$v" in
      .) echo "workspace" ;;
      *) echo "$v" ;;
    esac
    return 0
  fi
  # repo_map value (dir path) directly.
  if repo_map_has_value "$id" && [ -d "$WORKSPACE/$id/.git" ]; then
    echo "$id"; return 0
  fi
  echo ""; return 1
}

# resolve_repo_set(): parse the PRD `**Repos:**` header → canonical REPO_KEYS
# (array). Absent → backward-compatible single repo derived from Task `**Project:**`.
# Populates: REPO_KEYS (array), ROOT_IN_SET (bool), and per-repo manifest branch
# in REPO_MANIFEST_BRANCH[key].
declare -gA REPO_MANIFEST_BRANCH=()
resolve_repo_set() {
  local task_file="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  [ -f "$task_file" ] || die "Task file not found: $task_file"
  PROJECT="$(grep -m1 '^\*\*Project\*\*:' "$task_file" | sed 's/^\*\*Project\*\*: *//')"
  [ -z "$PROJECT" ] && PROJECT="software-factory"

  local repos_line=""
  if [ -n "${PRD:-}" ] && [ -f "$PRD" ]; then
    # `|| true` guards against pipefail: grep exits 1 when a PRD has no
    # `**Repos:**` header, and set -e would otherwise abort this assignment.
    repos_line="$(grep -m1 '^\*\*Repos\*\*:' "$PRD" 2>/dev/null | sed 's/^\*\*Repos\*\*: *//' || true)"
  fi
  local keys=()
  if [ -n "$repos_line" ]; then
    local id key
    while IFS= read -r id; do
      id="$(echo "$id" | tr -d ' \`')"
      [ -z "$id" ] && continue
      key="$(repo_key_for "$id")"
      if [ -z "$key" ]; then
        die "Unavailable repo '$id' declared in PRD **Repos:** — not in repo_map and no local checkout. Declare it in config/implementer.json or remove it from the PRD."
      fi
      keys+=("$key")
    done <<< "$(printf '%s\n' "$repos_line" | tr ',' '\n')"
  else
    # Backward compatible: single repo from Task **Project:**.
    local prj_repo; prj_repo="$(repo_map_path "$PROJECT")"
    if [ -z "$prj_repo" ] || [ "$prj_repo" = "." ]; then
      keys=(workspace)
    else
      keys=("$prj_repo")
    fi
  fi

  # Dedupe + collapse (e.g. software-factory + langfuse both → workspace).
  local seen=() out=() k
  for k in "${keys[@]}"; do
    if ! printf '%s\n' "${seen[@]}" | grep -qx "$k"; then
      seen+=("$k"); out+=("$k")
    fi
  done
  REPO_KEYS=("${out[@]}")

  ROOT_IN_SET=false
  for k in "${REPO_KEYS[@]}"; do [ "$k" = "workspace" ] && ROOT_IN_SET=true; done

  # Resolve each repo's manifest branch (workspace-portability manifest).
  local repo
  for repo in "${REPO_KEYS[@]}"; do
    local dir; dir="$repo"; [ "$repo" = "workspace" ] && dir="."
    REPO_MANIFEST_BRANCH["$repo"]="$(manifest_branch_for "$dir")"
  done

  echo "  Repo set (${#REPO_KEYS[@]}): ${REPO_KEYS[*]}" >&2
  echo "  Root touched: $ROOT_IN_SET" >&2
}

# manifest_branch_for <dir-path>: manifest branch for a repo (root '.' = master
# default). Reuses the workspace-portability manifest resolution.
manifest_branch_for() {
  local repo_dir="$1"
  python3 - "$repo_dir" "$WORKSPACE" <<'PYEOF'
import json, sys, os
repo, workspace = sys.argv[1], sys.argv[2]
manifest = os.path.join(workspace, "workspace-portability", "workspace_restore_manifest.json")
try:
    with open(manifest) as f:
        data = json.load(f)
    for r in data.get("repos", []):
        if r.get("path") == repo:
            print(r.get("branch", "master"))
            sys.exit(0)
except Exception:
    pass
print("master")
PYEOF
}

# assert_delivery_invariant(): the A/B XOR — (root code PR AND no bookkeeping PR)
# XOR (no root code PR AND exactly one bookkeeping PR). Dies loudly (exit 1) on a
# violation, printing the per-repo status table. Returns 0 on hold.
assert_delivery_invariant() {
  # In dry-run no real PRs exist — the invariant is asserted on real deliveries.
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] delivery invariant skipped (no real PRs in dry-run)" >&2
    return 0
  fi
  local has_root_code=false has_bk=false
  if [ "$ROOT_IN_SET" = true ]; then
    for k in "${!REPO_PR[@]}"; do
      [ "$k" = "workspace" ] && [ -n "${REPO_PR[$k]:-}" ] && has_root_code=true
    done
  else
    has_root_code=false
  fi
  [ -n "${BOOKKEEPING_PR:-}" ] && has_bk=true
  if { [ "$has_root_code" = true ] && [ "$has_bk" = true ]; } \
     || { [ "$has_root_code" = false ] && [ "$has_bk" = false ]; }; then
    echo "  FAILED: delivery invariant violated — root_code_pr=$has_root_code bookkeeping_pr=$has_bk" >&2
    for k in "${REPO_KEYS[@]}"; do
      echo "    $k: branch=${REPO_BRANCH[$k]:-} pr=${REPO_PR[$k]:-}" >&2
    done
    echo "    bookkeeping_pr=${BOOKKEEPING_PR:-}" >&2
    return 1
  fi
  echo "  ✓ delivery invariant holds (A/B XOR satisfied)" >&2
  return 0
}

# bookkeeping_tripwire <worktree> [<commit>]: hard-fail (return 1) if the
# given commit's changed paths include anything outside `docs/`. Defaults to
# HEAD (the bookkeeping commit, whose parent is the code commit in Shape B).
# This is the bdac29e-class guard that replaces `git add -A`.
bookkeeping_tripwire() {
  local wt="$1"; shift
  local commit="${1:-HEAD}"
  local parent; parent="$(git -C "$wt" rev-parse "$commit^" 2>/dev/null || true)"
  local files=""
  if [ -n "$parent" ]; then
    files="$(git -C "$wt" diff --name-only "$parent" "$commit" 2>/dev/null || true)"
  else
    files="$(git -C "$wt" diff --name-only --root "$commit" 2>/dev/null || true)"
  fi
  local bad=0 f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      docs/*) : ;;
      *) echo "  TRIPWIRE: bookkeeping commit touches non-docs path: $f" >&2; bad=1 ;;
    esac
  done <<< "$files"
  if [ "$bad" -eq 0 ]; then
    echo "  ✓ bookkeeping tripwire: changed paths are docs-only" >&2
    return 0
  fi
  echo "  FAILED: bookkeeping commit touches code paths (tripwire) — run aborted." >&2
  return 1
}

# write_run_manifest(): the run-manifest JSON is the monitoring backbone + the
# bookkeeping PR body source: per-repo {branch, pr, verdict, state}, bookkeeping_pr,
# root_code_pr, revisions, outcome, trips.
write_run_manifest() {
  local mf="${1:-$RUN_DIR/manifest.json}"
  local k; local -a jkeys=() jbranches=() jprs=() jverdicts=() jstates=()
  for k in "${REPO_KEYS[@]}"; do
    jkeys+=("$k")
    jbranches+=("${REPO_BRANCH[$k]:-}")
    jprs+=("${REPO_PR[$k]:-}")
    jverdicts+=("${REPO_VERDICT[$k]:-}")
    jstates+=("${REPO_STATE[$k]:-""}")
  done
  RUN_ID="${RUN_ID:-$(now_ts)}"
  python3 - "$mf" "$PRD_SLUG" "$RUN_ID" "${SHAPE_OUTCOME:-in-progress}" "${REVISIONS:-0}" \
    "${jkeys[*]}" "${jbranches[*]}" "${jprs[*]}" "${jverdicts[*]}" "${jstates[*]}" \
    "${BOOKKEEPING_PR:-}" "${ROOT_CODE_PR:-}" "${TRIPS_DOCS_ONLY:-true}" <<'PYEOF'
import json, sys
try:
    mf, task, run_id, outcome, revisions, keys, branches, prs, verdicts, states, bk, root_code, trips = sys.argv[1:14]
except Exception:
    mf, task, run_id, outcome, revisions = sys.argv[1:5]
    keys = branches = prs = verdicts = states = ""; bk = root_code = trips = ""
keys = keys.split() if keys and keys.strip() else []
branches = branches.split() if branches and branches.strip() else []
prs = prs.split() if prs and prs.strip() else []
verdicts = verdicts.split() if verdicts and verdicts.strip() else []
states = states.split() if states and states.strip() else []
def num(x):
    try: return int(x)
    except Exception: return None
repos = {}
for i, k in enumerate(keys):
    repos[k] = {
        "branch": branches[i] if i < len(branches) else "",
        "sha": "",
        "pr": num(prs[i]) if i < len(prs) else None,
        "verdict": verdicts[i] if i < len(verdicts) else "",
        "state": states[i] if i < len(states) else "",
    }
out = {
    "task": task, "run_id": run_id, "outcome": outcome,
    "revisions": int(revisions or 0), "repos": repos,
    "bookkeeping_pr": num(bk) if bk else None,
    "root_code_pr": num(root_code) if root_code else None,
    "trips": {"bookkeeping_docs_only": str(trips).lower() == "true"},
}
with open(mf, "w") as f:
    json.dump(out, f, indent=2)
PYEOF
  echo "  Run manifest written: $mf" >&2
}

# print_manifest(): surface the manifest table at the end of every run.
print_manifest() {
  local mf="${1:-$RUN_DIR/manifest.json}"
  [ -f "$mf" ] || { echo "  [manifest] none written" >&2; return 1; }
  echo "  ── Run manifest ($mf) ──" >&2
  python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
print("  task: %s | run_id: %s | outcome: %s | revisions: %s" % (m["task"], m["run_id"], m["outcome"], m["revisions"]))
for k, v in m["repos"].items():
    print("    repo: %-22s branch: %-42s pr: %-6s verdict: %-12s state: %s" % (k, v["branch"], v["pr"] or "-", v["verdict"] or "-", v["state"] or "-"))
print("  bookkeeping_pr: %s | root_code_pr: %s | trips.bookkeeping_docs_only: %s" % (m.get("bookkeeping_pr") or "-", m.get("root_code_pr") or "-", m.get("trips", {}).get("bookkeeping_docs_only")))
' "$mf" >&2
}

# gh_repo_for <repo-key>: the GitHub repo SLUG for a repo key (root → workspace
# remote). Derived from the local checkout's origin URL.
gh_repo_for() {
  local key="$1"
  local dir; dir="$key"; [ "$key" = "workspace" ] && dir="."
  local url; url="$(git -C "$WORKSPACE/$dir" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] && { echo "$url" | sed -E 's#.*/([^/]+)\.git#\1#; s#.*/([^/]+)#\1#'; return 0; }
  echo "workspace"
}

# raise_one_pr <repo-key> <worktree> <branch> <base> <gh-repo>: push the branch +
# `gh pr create` for ONE repo. Host-authored commit assumed already in the worktree.
# Sets REPO_BRANCH/REPO_PR. Returns non-zero on push/PR failure (fail-loud).
raise_one_pr() {
  local key="$1" wt="$2" branch="$3" base="$4" gh_repo="$5"
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would push branch $branch (repo $key) and raise a PR against $base" >&2
    REPO_BRANCH["$key"]="$branch"
    return 0
  fi
  if ! git -C "$wt" push -u origin "$branch"; then
    echo "  ERROR: git push of branch $branch (repo $key) failed — branch not pushed, no PR raised." >&2
    return 1
  fi
  echo "  Pushed branch $branch (repo $key)" >&2
  local title="[factory] ${PRD_SLUG}: implementer run ($(now_human)) — $key"
  local body_file="$RUN_DIR/pr-body-$key.md"
  {
    echo "## Implementer Run"
    echo ""
    echo "Task: \`${PRD_SLUG}\` (repo: \`$key\`)"
    echo "Impl session: \`$IMPL_UUID\`"
    echo ""
    echo "### Report"
    echo ""
    if [ -f "$ARCHIVE_DEST/report.md" ]; then cat "$ARCHIVE_DEST/report.md"; fi
  } > "$body_file"
  command -v gh >/dev/null 2>&1 || { echo "  ERROR: gh not installed; PR skipped (branch already pushed, repo $key)." >&2; return 1; }
  gh label create "factory:needs-review" --repo "ak47-arch/$gh_repo" --force >/dev/null 2>&1 || true
  local attempt=0 pr_url=""
  while [ "$attempt" -lt 3 ] && [ -z "$pr_url" ]; do
    attempt=$((attempt+1))
    if pr_url="$(gh pr create --repo "ak47-arch/$gh_repo" --base "$base" --head "$branch" \
        --title "$title" --body-file "$body_file" --label "factory:needs-review")"; then
      :
    else
      if [ "$attempt" -lt 3 ]; then
        echo "  WARN: gh pr create attempt $attempt/3 failed (transient?) — retrying." >&2
        sleep "$attempt"; pr_url=""
      fi
    fi
  done
  if [ -z "$pr_url" ]; then
    echo "  ERROR: gh pr create failed after 3 attempts (branch remains pushed, repo $key)." >&2
    return 1
  fi
  echo "  PR raised ($key): $pr_url (tagged factory:needs-review)." >&2
  local pr_num; pr_num="$(printf '%s' "$pr_url" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
  REPO_BRANCH["$key"]="$branch"
  REPO_PR["$key"]="$pr_num"
  return 0
}

# deliver_shape_b_root <worktree> <branch> <base> <gh-repo>: Shape B collapse for
# the root repo — the branch carries a CODE commit then a BOOKKEEPING commit
# (docs-only), pushed as ONE PR. Runs the docs-only tripwire on the bookkeeping
# commit. Sets REPO_PR[workspace] + ROOT_CODE_PR.
deliver_shape_b_root() {
  local wt="$1" branch="$2" base="$3" gh_repo="$4"
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] Shape B: would commit code then bookkeeping on $branch (workspace) → 1 root PR" >&2
    REPO_BRANCH["workspace"]="$branch"
    return 0
  fi
  # 1. Code commit: stage everything EXCEPT docs/ (docs ride the bookkeeping commit).
  git -C "$wt" add -A ':(exclude)docs/**' 2>/dev/null \
    || git -C "$wt" add -A
  if git -C "$wt" diff --cached --quiet; then
    echo "  [no-op] root repo has no code changes beyond base — no code commit." >&2
  else
    git -C "$wt" -c user.name="${IMPL_GIT_NAME:-factory}" \
        -c user.email="${IMPL_GIT_EMAIL:-factory@ak47.local}" commit -q \
        -m "implementer($PRD_SLUG): run $IMPL_UUID [factory] (workspace) [code]" \
      || { echo "  ERROR: Shape B code commit failed (workspace)." >&2; return 2; }
  fi
  # 2. Bookkeeping commit: docs/ only (manifest + archived bookkeeping doc).
  local bkdir="$wt/docs/implementations/$(date '+%Y-%m-%d')-$PRD_SLUG"
  mkdir -p "$bkdir"
  write_run_manifest "$bkdir/manifest.json" 2>/dev/null || true
  git -C "$wt" add -A docs/ 2>/dev/null || true
  if git -C "$wt" diff --cached --quiet; then
    echo "  [no-op] no bookkeeping content to commit (workspace)." >&2
  else
    git -C "$wt" -c user.name="${IMPL_GIT_NAME:-factory}" \
        -c user.email="${IMPL_GIT_EMAIL:-factory@ak47.local}" commit -q \
        -m "implementer($PRD_SLUG): bookkeeping [factory] run $IMPL_UUID" \
      || { echo "  ERROR: bookkeeping commit failed (workspace)." >&2; return 2; }
  fi
  # 3. Docs-only tripwire on the bookkeeping commit (HEAD).
  if ! bookkeeping_tripwire "$wt" HEAD; then
    TRIPS_DOCS_ONLY=false
    return 1
  fi
  # 4. Push + PR (one root PR carries code + bookkeeping commits).
  if ! raise_one_pr "workspace" "$wt" "$branch" "$base" "$gh_repo"; then
    return 1
  fi
  ROOT_CODE_PR="${REPO_PR[workspace]:-}"
  return 0
}

# deliver_repo_set(): per-repo delivery across REPO_KEYS. Shape A repos get
# their own PRs; a touched root gets Shape B collapse (code+bookkeeping on one
# branch/PR). Asserts the A/B invariant + writes + prints the run manifest.
deliver_repo_set() {
  local key
  for key in "${REPO_KEYS[@]}"; do
    local branch="factory/$PRD_SLUG/$key/$(now_ts)"
    local base="${REPO_MANIFEST_BRANCH[$key]:-master}"
    local dir="$RUN_DIR/worktrees/$key"
    # Single-repo task: the root worktree lives at RUN_DIR/worktree (from
    # prepare_run_dir); multi-repo tasks use RUN_DIR/worktrees/<key>/.
    if [ ! -d "$dir/.git" ] && [ "${#REPO_KEYS[@]}" -eq 1 ]; then
      dir="$RUN_DIR/worktree"
    fi
    local gh_repo; gh_repo="$(gh_repo_for "$key")"
    [ -d "$dir/.git" ] || { echo "  ERROR: worktree missing for repo $key ($dir) — prepare_run_dirs did not create it." >&2; return 1; }
    # The worktree may be on the prepare_run_dir branch (single) or an app
    # worktree's checkout branch — retarget it at the delivery branch so the
    # push refspec below resolves. Uncommitted implementer changes are kept
    # (both branches point at the same commit for a clean checkout).
    git -C "$dir" checkout -q -B "$branch" 2>/dev/null || true
    if [ "$key" = "workspace" ] && [ "$ROOT_IN_SET" = true ]; then
      deliver_shape_b_root "$dir" "$branch" "$base" "$gh_repo" || return $?
    else
      # Shape A: commit any implementer changes, then push + PR.
      if [ "$DRY_RUN" != true ]; then
        git -C "$dir" add -A
        if ! git -C "$dir" diff --cached --quiet; then
          git -C "$dir" -c user.name="${IMPL_GIT_NAME:-factory}" \
              -c user.email="${IMPL_GIT_EMAIL:-factory@ak47.local}" commit -q \
              -m "implementer($PRD_SLUG): run $IMPL_UUID [factory] ($key)" \
            || { echo "  ERROR: could not commit worktree changes (repo $key)." >&2; return 2; }
        else
          echo "  [no-op] repo $key has no changes beyond base — skipping empty PR." >&2
          continue
        fi
      fi
      if ! raise_one_pr "$key" "$dir" "$branch" "$base" "$gh_repo"; then
        echo "  FAILED: partial delivery (repo $key) — aborting; per-repo status:" >&2
        for k in "${REPO_KEYS[@]}"; do echo "    $k: branch=${REPO_BRANCH[$k]:-} pr=${REPO_PR[$k]:-}" >&2; done
        return 1
      fi
    fi
  done
  # Invariant + manifest after every delivery.
  assert_delivery_invariant || return 1
  write_run_manifest
  print_manifest
  return 0
}

# ─── prepare_run_dir(): worktree + outbox + brief ──────────────────────────
prepare_run_dir() {
  local ts; ts="$(now_ts)"
  IMPL_UUID="$(new_uuid)"
  RUN_DIR="$RUNS_ROOT/$PRD_SLUG-$ts"
  WORKTREE="$RUN_DIR/worktree"
  OUTBOX="$RUN_DIR/outbox"
  SESSION_LOG="$RUN_DIR/session.jsonl"
  WORKTREE="$RUN_DIR/worktree"
  mkdir -p "$OUTBOX/decisions" "$RUN_DIR/sessions"
  echo "  Run dir: $RUN_DIR" >&2
  echo "  Impl session UUID: $IMPL_UUID" >&2

  # Target repo, resolved to an absolute path on the host (for clone + push).
  local src_repo; src_repo="$WORKSPACE/$TARGET_REPO"
  [ -d "$src_repo/.git" ] || die "Target repo not a git repo: $src_repo"

  # Self-contained clone in the run dir — NOT a host git worktree. A host
  # `git worktree .git` points at the host repo's common dir, which lives on
  # the read-only /workspace mount and therefore cannot be committed into from
  # inside the container. A full clone keeps all git metadata inside the
  # writable /sandbox run dir, so the implementer commits natively.
  local branch="factory/$PRD_SLUG/$ts"
  git clone --quiet --local "$src_repo" "$WORKTREE" 2>/dev/null \
    || git clone --quiet "$src_repo" "$WORKTREE"
  git -C "$WORKTREE" checkout -q -B "$branch" "origin/$MANIFEST_BRANCH" 2>/dev/null \
    || git -C "$WORKTREE" checkout -q -B "$branch" "$MANIFEST_BRANCH"
  # Keep a pristine manifest branch ref so the push below can target it.
  git -C "$WORKTREE" branch "refs/heads/origin-$MANIFEST_BRANCH" \
    "origin/$MANIFEST_BRANCH" 2>/dev/null || true
  # Point origin at the REAL remote (clone --local sets it to the local path).
  local real_url
  real_url="$(git -C "$src_repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$real_url" ]; then
    git -C "$WORKTREE" remote set-url origin "$real_url"
  fi
  # A fresh clone has NO git identity, so `git commit` (run by the host at
  # delivery time) would fail with "Author identity unknown". Set local config
  # so the host-authored commit actually lands — this is the driver's identity.
  git -C "$WORKTREE" config user.name "${IMPL_GIT_NAME:-factory}"
  git -C "$WORKTREE" config user.email "${IMPL_GIT_EMAIL:-factory@ak47.local}"
  WORKTREE_BRANCH="$branch"
  echo "  Worktree clone: $WORKTREE (branch $branch, base $MANIFEST_BRANCH)" >&2

  # Build the verification-commands hint from the PRD's Testing decisions.
  local verify_hint="See the PRD `## Testing decisions` for the acceptance commands. Run them inside the worktree as the PRD specifies."

  write_brief "$verify_hint"
  # Register the root worktree in the multi-repo map (Shape B root delivery).
  REPO_WORKTREE["workspace"]="$WORKTREE"
}

# ─── prepare_run_dirs(): additional app-repo worktrees for a multi-repo task ─
# Creates RUN_DIR/worktrees/<key>/ for every non-root REPO_KEYS entry (the root
# worktree already exists at RUN_DIR/worktree from prepare_run_dir). One clone
# per repo, branch factory/<slug>/<key>/<ts> from that repo's manifest branch.
prepare_run_dirs() {
  local key
  for key in "${REPO_KEYS[@]}"; do
    [ "$key" = "workspace" ] && continue
    local src_repo="$WORKSPACE/$key"
    [ -d "$src_repo/.git" ] || die "Target repo not a git repo: $src_repo"
    local wt="$RUN_DIR/worktrees/$key"
    local base="${REPO_MANIFEST_BRANCH[$key]:-master}"
    local branch="factory/$PRD_SLUG/$key/$(now_ts)"
    git clone --quiet --local "$src_repo" "$wt" 2>/dev/null \
      || git clone --quiet "$src_repo" "$wt"
    git -C "$wt" checkout -q -B "$branch" "origin/$base" 2>/dev/null \
      || git -C "$wt" checkout -q -B "$branch" "$base"
    git -C "$wt" branch "refs/heads/origin-$base" "origin/$base" 2>/dev/null || true
    local real_url; real_url="$(git -C "$src_repo" remote get-url origin 2>/dev/null || true)"
    if [ -n "$real_url" ]; then git -C "$wt" remote set-url origin "$real_url"; fi
    git -C "$wt" config user.name "${IMPL_GIT_NAME:-factory}"
    git -C "$wt" config user.email "${IMPL_GIT_EMAIL:-factory@ak47.local}"
    REPO_WORKTREE["$key"]="$wt"
    echo "  App worktree: $wt (branch $branch, base $base)" >&2
  done
  echo "  ${#REPO_KEYS[@]} repo worktrees prepared under $RUN_DIR/worktrees/" >&2
}

write_brief() {
  cat > "$RUN_DIR/brief.md" <<EOF
# Implementer Task Brief

- **PRD path**: ${PRD#/workspace/} (read-only; also below)
- **Task slug**: $PRD_SLUG
- **Impl session UUID**: $IMPL_UUID
- **Worktree path** (read-write; your working directory): /sandbox/worktree
- **Outbox path** (write results here): /sandbox/outbox

## Rules (binding)

1. Implement EVERY user story in the PRD, one story/unit at a time.
2. Work ONLY inside /sandbox/worktree. Your edits are already durable on the
   host's disk via this mount — you do NOT need to commit anything.
3. Do NOT run ANY git command (no init/add/commit/stash/push/pull/checkout).
   The host driver performs the single commit, push, and PR at the end.
4. You CANNOT modify docs/tasks/, docs/tasks.txt, or docs/prd-queue/ — those
   live in the read-only /workspace mount. Do not attempt to bypass this.
5. Do NOT write secrets, keys, or GitHub credentials anywhere.
6. Do NOT run builds that require network secrets you don't have.

## Verification

$1
- State evidence for each story (what you changed and how it is verified).

## Completion

Write /sandbox/outbox/report.md (per-story done/not-done + evidence +
verification results + UAT hand-off list) and any emerged decisions to
/sandbox/outbox/decisions/NN-<slug>.md (structured decision format), then exit 0.
On partial failure, still write the report and exit 1.
EOF
  echo "  Brief written: $RUN_DIR/brief.md" >&2
}

# ─── transition(): lifecycle transition (simulated under --dry-run) ────────
transition() {
  local to="$1"; shift
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would transition $PRD_SLUG → $to" >&2
    return 0
  fi
  local session_flag=""
  if [ "$to" = "in-progress" ]; then
    session_flag="--session $IMPL_UUID:implementation"
  fi
  "$WORKSPACE/bin/transition-task.sh" "$PRD_SLUG" --to "$to" $session_flag "$@"
}

# ─── Write impl session header ─────────────────────────────────────────────
write_session_header() {
  mkdir -p "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"
  if [ ! -f "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl" ]; then
    {
      printf '{"type":"session","uuid":"%s","task":"%s","project":"%s","driver":"implementer-run.sh","start":"%s"}\n' \
        "$IMPL_UUID" "$PRD_SLUG" "$PROJECT" "$(now_human)"
    } > "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl"
  fi
  echo "  Session log: docs/knowledge/sessions/$IMPL_UUID/session.jsonl" >&2
}

# ─── Build filtered secrets env-list ───────────────────────────────────────
write_env_file() {
  local envfile="$RUN_DIR/secrets.env"
  : > "$envfile"
  chmod 600 "$envfile"
  local name
  while read -r name; do
    [ -z "$name" ] && continue
    # allowlist entries must be valid environment-variable identifiers (a
    # glob like `LANGFUSE_*` or an empty pattern must not crash ${!name}).
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [ -n "${!name:-}" ]; then
      printf '%s=%s\n' "$name" "${!name}" >> "$envfile"
    fi
  done < <(env_allowed)
  # Force the ponytail default mode into the container (config-driven).
  if [ -n "$PONYTAIL_DEFAULT_MODE" ]; then
    printf 'PONYTAIL_DEFAULT_MODE=%s\n' "$PONYTAIL_DEFAULT_MODE" >> "$envfile"
  fi
  # ── LLM credential fallback from pi's auth.json (the same file pi reads) ──
  # For allowlisted provider env vars left unset by the host env, resolve the
  # key from ~/.pi/agent/auth.json. Scoped strictly to the allowlist mapping —
  # the github-copilot access token and the nvidia key never enter the
  # container. Values go straight to the envfile, never echoed.
  local auth_file="${PI_AUTH_FILE:-$HOME/.pi/agent/auth.json}"
  if [ -f "$auth_file" ]; then
    local name provider key
    while read -r name; do
      [ -z "$name" ] && continue
      case "$name" in
        OPENROUTER_API_KEY) provider=openrouter ;;
        ANTHROPIC_API_KEY)  provider=anthropic ;;
        *) continue ;;
      esac
      if ! grep -q "^${name}=" "$envfile"; then
        key="$(python3 -c '
import json, sys
provider, auth_file = sys.argv[1], sys.argv[2]
try:
    with open(auth_file) as f:
        auth = json.load(f)
    sys.stdout.write(auth.get(provider, {}).get("key", ""))
except Exception:
    sys.exit(1)
' "$provider" "$auth_file")" || continue
        if [ -n "$key" ]; then
          printf '%s=%s\n' "$name" "$key" >> "$envfile"
        fi
      fi
    done < <(env_allowed)
  fi
  # Env must contain ONLY LLM + Langfuse credentials + the mode variable —
  # never GH tokens.
  echo "$envfile"
}

# ─── ponytail_skill_flags(): the six implementer `--skill` flags (Decision 04)
# Testable seam + used by run_container. The skills are bind-mounted read-only
# at the fixed container path /skills (not inherited from a host checkout);
# implementer-scoped, never touches shared .pi/settings.json.
PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help)
ponytail_skill_flags() {
  local s
  for s in "${PONYTAIL_SKILL_NAMES[@]}"; do
    printf '%s\n' "--skill $PONYTAIL_SKILLS_DIR/$s"
  done
}

# ─── run_container(): one podman attempt, streamed live ────────────────────
# Returns 0 on implementer success (report present), 1 on container/impl failure.
run_container() {
  local attempt="$1"
  local envfile; envfile="$(write_env_file)"

  local model_arg=()
  if [ -n "${IMPLEMENTER_MODEL:-}" ]; then
    model_arg=(--model "$IMPLEMENTER_MODEL")
  elif [ -n "${MODEL:-}" ] && [ "$MODEL" != "null" ]; then
    model_arg=(--model "$MODEL")
  elif [ -n "${PI_MODEL:-}" ]; then
    model_arg=(--model "${PI_PROVIDER:-openrouter}/${PI_MODEL}")
  fi

  # The six ponytail skills, bind-mounted read-only from the host skills
  # checkout at /skills. If the host checkout is absent, warn loudly and run
  # WITHOUT the flags/mount (ponytail is advisory — never a blocker, never a
  # fabrication incentive; warn-and-run, never silent, never fail-fast).
  local pony=()
  local skills_mount=()
  if [ -d "$HOST_SKILLS" ]; then
    while IFS= read -r flag; do pony+=($flag); done < <(ponytail_skill_flags)
    skills_mount=(-v "$HOST_SKILLS:/skills:ro")
  else
    echo "WARN: ponytail skills not found at ${HOST_SKILLS:-<unset>}; running without ponytail discipline" >&2
  fi

  local container_out="$RUN_DIR/container-$attempt.log"

  echo "  [attempt $attempt/$RESPAWN_CAP] podman run $IMAGE ..." >&2

  # Deterministic container identity so we can shut it down explicitly once the
  # PR is raised (defensive: --rm already removes it on exit, but this also
  # handles stale containers left by prior runs and name conflicts on respawn).
  local cname="impl-$IMPL_UUID"
  if command -v "${IMPLEMENTER_PODMAN_BIN:-podman}" >/dev/null 2>&1; then
    podman_call rm -f "$cname" >/dev/null 2>&1 || true
  fi

  # Continuity is native: pi persists its session to the host mount under the
  # run's session-dir, and a respawn (or a revision resuming the original
  # session — decision 08) passes --continue so the fresh container resumes the
  # existing conversation (no PROGRESS.md needed). In revise mode the seeded
  # `sessions/` dir holds the original session file, so --continue is set from
  # attempt 1.
  local sess_args=(--session-dir /sandbox/sessions)
  if [ "$REVISION_MODE" = true ] || [ "$attempt" -gt 1 ]; then
    sess_args+=(--continue)
  fi

  local directive
  if [ "$REVISION_MODE" = true ]; then
    directive="Execute your implementer REVISION run now. Read /sandbox/brief.md and the PRD it references. The review findings at /sandbox/review/report.md (and /sandbox/review/decisions/) are the BINDING fix authority: fix EXACTLY what they scope — no more, no less — and WHERE THEY CONFLICT WITH YOUR EARLIER REASONING, THE FINDINGS WIN. Resume your original implementation session context — do NOT restart from scratch, do NOT re-litigate findings, do NOT expand scope beyond the findings. Do NOT run any git commands (the host owns git) and do NOT change the task lifecycle. Implement the fix in /sandbox/worktree (the SAME branch as the original PR), run the PRD verification commands, then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  elif [ "$attempt" -eq 1 ]; then
    directive="Execute your implementer run contract now. Read /sandbox/brief.md and the PRD it references, implement every user story in /sandbox/worktree (do NOT run any git commands — the host owns git), run the PRD verification commands, then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  else
    directive="Resume your interrupted implementer run. You were killed mid-run; this container continues the SAME session, and your edits are already on disk in /sandbox/worktree. Continue from where you left off — do NOT restart from scratch. Finish implementing every story per /sandbox/brief.md (do NOT run any git commands — the host owns git), run verification, then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  fi

  local exit_code=0
  # Live-stream container stdout into the session log while it runs.
  # NOTE: no `exec` here — podman_call is a function seam, not an external
  # command, so the subshell simply runs it and exits when it returns (mirrors
  # review-run.sh podman_call).
  (
    podman_call run --rm --network=host \
      --name "impl-$IMPL_UUID" \
      -v "$WORKSPACE:/workspace:ro" \
      "${skills_mount[@]}" \
      -v "$RUN_DIR:/sandbox" \
      --env-file "$envfile" \
      "$IMAGE" \
      pi --mode json -p \
        "${sess_args[@]}" \
        "${pony[@]}" \
        --append-system-prompt /sandbox/brief.md \
        --append-system-prompt /workspace/.pi/agents/implementer.md \
        "${model_arg[@]}" \
        "$directive"
  ) > "$container_out" 2>&1 & local pid=$!

  # Liveness watch: tail-running, plus a hard overall timeout. The idle watchdog
  # keys on new bytes; a long-running tool (e.g. `... | tail`) emits nothing until
  # it finishes, so we skip the idle-kill while a tool_execution is open — the
  # hard timeout below still bounds the run.
  local deadline=$(( $(date +%s) + TIMEOUT_SEC ))
  local last_activity=0
  local last_size=0
  local tool_open=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ $(date +%s) -ge "$deadline" ]; then
      echo "  [timeout] run exceeded ${TIMEOUT_SEC}s — terminating container." >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    # Append any new bytes since last poll to the session log (live stream).
    if [ -f "$container_out" ]; then
      local size; size=$(wc -c < "$container_out")
      if [ "$size" -gt "$last_size" ]; then
        local slice; slice=$(tail -c +$((last_size+1)) "$container_out")
        printf '%s' "$slice" >> "$SESSION_LOG"
        # Track whether a tool is currently executing (start minus end).
        local s; s=$(printf '%s' "$slice" | grep -c '"type":"tool_execution_start"' || true)
        local e; e=$(printf '%s' "$slice" | grep -c '"type":"tool_execution_end"' || true)
        tool_open=$((tool_open + s - e)); [ "$tool_open" -lt 0 ] && tool_open=0
        last_size="$size"
        last_activity=$(date +%s)
      fi
    fi
    # Idle watchdog: no new output for LIVENESS_IDLE seconds while idle (no tool
    # execution open) → unhealthy. A quiet-but-running tool is left alone.
    if [ "$tool_open" -eq 0 ] && [ "$last_activity" -ne 0 ] && [ $(( $(date +%s) - last_activity )) -gt "$LIVENESS_IDLE" ]; then
      echo "  [liveness] no output for ${LIVENESS_IDLE}s (no tool running) — treating as stuck." >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep "$LIVENESS_INTERVAL"
  done
  wait "$pid" || exit_code=$?

  # Drain final output.
  if [ -f "$container_out" ]; then
    local size; size=$(wc -c < "$container_out")
    if [ "$size" -gt "$last_size" ]; then
      tail -c +$((last_size+1)) "$container_out" >> "$SESSION_LOG"
    fi
  fi

  if [ -f "$OUTBOX/report.md" ]; then
    echo "  [attempt $attempt] implementer completed with report; exit=$exit_code" >&2
    return 0
  fi
  echo "  [attempt $attempt] implementer did not complete; exit=$exit_code" >&2
  return 1
}

# ─── archive(): copy outbox → docs/implementations/<date>-<slug>/ ──────────
archive() {
  local ts; ts="$(date '+%Y-%m-%d')"
  local dest="$WORKSPACE/$ARCHIVES_ROOT/$ts-$PRD_SLUG"
  mkdir -p "$dest/decisions"
  if [ -f "$OUTBOX/report.md" ]; then
    cp "$OUTBOX/report.md" "$dest/report.md"
  fi
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$dest/decisions/" 2>/dev/null || true
  fi
  # Keep a copy of the brief for auditability.
  cp "$RUN_DIR/brief.md" "$dest/brief.md"
  echo "  Archived run artifacts → $dest" >&2
  ARCHIVE_DEST="$dest"
}

# ─── append index entries via the deterministic sorter ─────────────────────
append_decisions_to_index() {
  # The driver (never the model) owns docs/knowledge/index.md. First mirror any
  # outbox decisions into the impl session dir (the driver archives them there
  # too, following the knowledge-base convention), then add index links by
  # re-running the deterministic sorter.
  local sess_dir="$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"
  mkdir -p "$sess_dir/decisions"
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$sess_dir/decisions/" 2>/dev/null || true
  fi
  local idx="$WORKSPACE/docs/knowledge/index.md"
  local proj="$PROJECT"
  # Ensure a project section exists, then insert entry lines (driver-only).
  if ! grep -q "^### $proj" "$idx"; then
    printf '\n### %s\n' "$proj" >> "$idx"
  fi
  local d
  for d in "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"/decisions/*.md; do
    [ -f "$d" ] || continue
    local base; base="$(basename "$d")"
    local title; title="$(echo "$base" | sed -E 's/^[0-9]+-//; s/\.md$//; s/-/ /g')"
    if ! grep -Fq "sessions/$IMPL_UUID/decisions/$base" "$idx"; then
      # Insert under the project section (driver-side append).
      python3 - "$idx" "$proj" "$title" "$IMPL_UUID" "$base" <<'PYEOF'
import sys
path, proj, title, uuid, base = sys.argv[1:6]
with open(path) as f:
    lines = f.read().split('\n')
out = []
inserted = False
for line in lines:
    out.append(line)
    if line.strip() == f'### {proj}' and not inserted:
        out.append(f'- [{title}](sessions/{uuid}/decisions/{base})')
        inserted = True
with open(path, 'w') as f:
    f.write('\n'.join(out) + '\n')
PYEOF
    fi
  done
  python3 "$WORKSPACE/bin/sort-knowledge-index.py" >/dev/null
  echo "  Appended + re-sorted decision index entries." >&2
}

# ─── push + PR (driver-only; skipped under --dry-run) ──────────────────────
push_and_pr() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would push branch $WORKTREE_BRANCH and raise a PR against $MANIFEST_BRANCH" >&2
    return 0
  fi
  # Host authors the single commit from the implementer's files (the implementer
  # never touches git). Commit everything the model wrote in the worktree.
  git -C "$WORKTREE" add -A
  if ! git -C "$WORKTREE" diff --cached --quiet; then
    # -c identity is belt-and-suspenders; prepare_run_dir also sets local config.
    if ! git -C "$WORKTREE" -c user.name="${IMPL_GIT_NAME:-factory}" \
          -c user.email="${IMPL_GIT_EMAIL:-factory@ak47.local}" commit -q \
          -m "implementer($PRD_SLUG): run $IMPL_UUID [factory]"; then
      echo "  ERROR: could not commit worktree changes (no diff or identity)." >&2
      return 2
    fi
  else
    echo "  [no-op] worktree has no changes beyond base — nothing to commit." >&2
  fi
  echo "  Host-authored worktree commit on $WORKTREE_BRANCH" >&2
  # Push the worktree branch (commits live in the run-dir clone, not src).
  # origin in the clone already points at the real remote. Under `set -e` the
  # `if !` guard tells the shell the function is being checked, so a failed
  # push must be surfaced EXPLICITLY (return non-zero) rather than relying on
  # set -e, and the truthfulness discipline means we never print "Pushed
  # branch …" unless the push actually landed.
  if ! git -C "$WORKTREE" push -u origin "$WORKTREE_BRANCH"; then
    echo "  ERROR: git push of branch $WORKTREE_BRANCH failed (branch not pushed, no PR raised)." >&2
    return 1
  fi
  echo "  Pushed branch $WORKTREE_BRANCH" >&2

  # Raise the PR with title/body derived from the brief + report.
  local title="[factory] ${PRD_SLUG}: implementer run ($(now_human))"
  local body_file="$RUN_DIR/pr-body.md"
  {
    echo "## Implementer Run"
    echo ""
    echo "Task: \`${PRD_SLUG}\`"
    echo "Impl session: \`${IMPL_UUID}\`"
    echo ""
    echo "### Report"
    echo ""
    if [ -f "$ARCHIVE_DEST/report.md" ]; then cat "$ARCHIVE_DEST/report.md"; fi
  } > "$body_file"

  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not installed; PR skipped (branch already pushed)." >&2; return 1; }
  # Derive the GitHub repo slug from the source repo's origin URL.
  local gh_repo
  gh_repo="$(git -C "$WORKSPACE/$TARGET_REPO" remote get-url origin 2>/dev/null \
    | sed -E 's#.*/([^/]+)\.git#\1#; s#.*/([^/]+)#\1#' )"
  [ -z "$gh_repo" ] && gh_repo="workspace"
  # Ensure the factory label family exists once so the --label below never
  # fails on a fresh repo (Decision 01: inert metadata for review --pick).
  gh label create "factory:needs-review" --repo "ak47-arch/$gh_repo" --force >/dev/null 2>&1 || true
  local pr_url
  # Transient GitHub API failures (HTTP 503 etc.) are common enough that a
  # single-shot `gh pr create` kills otherwise-good runs. Retry with backoff;
  # on persistent failure, leave the branch pushed and return non-zero so the
  # caller can route to fail_run (never print a misleading "PR raised").
  local attempt=0 pr_url=""
  while [ "$attempt" -lt 3 ] && [ -z "$pr_url" ]; do
    attempt=$((attempt+1))
    if pr_url="$(gh pr create \
      --repo "ak47-arch/$gh_repo" \
      --base "$MANIFEST_BRANCH" --head "$WORKTREE_BRANCH" \
      --title "$title" --body-file "$body_file" \
      --label "factory:needs-review")"; then
      :
    else
      if [ "$attempt" -lt 3 ]; then
        echo "  WARN: gh pr create attempt $attempt/3 failed (transient?) — retrying in ${attempt}s." >&2
        sleep "$attempt"
        pr_url=""
      fi
    fi
  done
  if [ -z "$pr_url" ]; then
    echo "  ERROR: gh pr create failed after 3 attempts (branch remains pushed)." >&2
    return 1
  fi
  echo "  PR raised: $pr_url (tagged factory:needs-review)." >&2

  # Decision 06: attach PR tracking to the task file (raise hook).
  local pr_num head_sha
  pr_num="$(printf '%s' "$pr_url" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
  head_sha="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || echo '?')"
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/bin/lib-pr-tracking.sh"
  local task="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  if [ -n "$pr_num" ] && pr_tracking_ensure "$task" && ! pr_tracking_has "$task" "PR: #$pr_num "; then
    pr_tracking_add "$task" "- PR: #$pr_num (ak47-arch/$gh_repo)"
    pr_tracking_add "$task" "- URL: $pr_url"
    pr_tracking_add "$task" "- Branch: $WORKTREE_BRANCH"
    pr_tracking_add "$task" "- Base: $MANIFEST_BRANCH · Head: $head_sha (raised $(date '+%Y-%m-%d %H:%M'))"
    pr_tracking_add "$task" "- Raised by: implementer run $IMPL_UUID"
    ( cd "$WORKSPACE" && git add "docs/tasks/$PRD_SLUG.md" 2>/dev/null || true
      git diff --cached --quiet || git commit -q -m "task($PRD_SLUG): record PR #$pr_num (tracking)" )
    echo "  Task PR tracking: #$pr_num recorded on docs/tasks/$PRD_SLUG.md" >&2
  fi
}

# ─── stop_container(): ensure the run's sandbox container is shut down ────
# The container is cattle: once the PR is raised (or the run fails) it is no
# longer needed. Containers run with --rm, so this is mostly defensive — it
# also cleans stale containers from prior runs that died mid-flight.
stop_container() {
  local cname="impl-$IMPL_UUID"
  if command -v "${IMPLEMENTER_PODMAN_BIN:-podman}" >/dev/null 2>&1 \
      && podman_call ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
    echo "  Shutting down sandbox container $cname (no longer needed)." >&2
    podman_call stop -t 5 "$cname" >/dev/null 2>&1 || true
    podman_call rm -f "$cname" >/dev/null 2>&1 || true
  fi
}

# ─── cleanup_run_dir(): enforce disposable-vs-durable after a run ──────────
# Removes the throwaway residue a run accumulates (installed deps, raw trace
# logs) so the host doesn't accrete ~300 MB of bloat per task. Everything
# durable survives: outbox/report/decisions, the compact native session
# evidence (sessions/), the brief, the PR body, and the worktree source (with
# deps stripped).
#
# Flags: --keep-logs  preserve raw container logs + streamed transcript
#        (used on the failure path, where logs are the diagnosis)
# Controls: IMPL_CLEANUP=false disables; KEEP_WORKTREE=0 deletes the worktree
#        (and its .git) completely instead of just stripping deps.
cleanup_run_dir() {
  local keep_logs=false
  [ "${1:-}" = "--keep-logs" ] && keep_logs=true
  local deps=0
  # 1. Throwaway dependency trees inside the worktree (never committed;
  #    rebuildable from package.json/requirements.txt).
  if [ -d "$WORKTREE" ]; then
    while IFS= read -r -d '' d; do
      rm -rf "$d" && deps=$((deps+1))
    done < <(find "$WORKTREE" -type d \( -name node_modules -o -name 'venv*' \
      -o -name .venv -o -name __pycache__ -o -name .pytest_cache \) \
      -prune -print0 2>/dev/null || true)
    find "$WORKTREE" -name '*.pyc' -delete 2>/dev/null || true
  fi
  # 2. Raw per-run trace (the native evidence copy survives in sessions/; the
  #    finalized transcript lives in docs/knowledge/sessions/<uuid>/).
  if [ "$keep_logs" = false ]; then
    rm -f "$RUN_DIR"/container-*.log "$RUN_DIR"/session.jsonl
  fi
  # 3. Re-injectable env file — never needed again; regenerated per run.
  rm -f "$RUN_DIR"/secrets.env
  if [ "$KEEP_WORKTREE" = "0" ] && [ -d "$WORKTREE" ]; then
    rm -rf "$WORKTREE"
  fi
  echo "  Cleanup: removed $deps disposable dep dirs + raw trace from $RUN_DIR (durable artifacts kept)." >&2
}

# ─── failure path ──────────────────────────────────────────────────────────
fail_run() {
  local reason="$1"
  echo "  FAILED: $reason" >&2
  stop_container
  if [ "$DRY_RUN" != true ] && [ "${IMPL_CLEANUP:-$CLEANUP_ENABLED}" != "false" ]; then
    cleanup_run_dir --keep-logs
  fi
  if [ -d "$OUTBOX" ] && [ -f "$OUTBOX/report.md" ]; then
    archive
  elif [ -d "$OUTBOX" ]; then
    # Write a partial report so the failure is durable.
    cp "$RUN_DIR/brief.md" "$OUTBOX/partial-report.md" 2>/dev/null || true
    echo "# Partial report" > "$OUTBOX/report.md"
    echo "" >> "$OUTBOX/report.md"
    echo "Run failed: $reason" >> "$OUTBOX/report.md"
    archive
  fi
  # D3: a revision never transitions the task lifecycle — it stays in-review
  # through the re-review. Only the normal (non-revise) failure path reverts the
  # task to prd-ready.
  if [ "$REVISION_MODE" != true ]; then
    transition "prd-ready"
  fi
  exit 1
}

# ═══════════════════════════════════════════════════════════════════════════
# Revision mode (decision 08) — --revise <pr> resumes the ORIGINAL impl session
# to address review findings on an open PR. The task file (decision 06 PR
# tracking) is the join: PR → slug (title) → original impl session UUID
# ("Raised by: implementer run <uuid>") → newest REQUEST_CHANGES review.
# ═══════════════════════════════════════════════════════════════════════════

# json_get <field>: read a scalar field from stdin JSON (tiny gh-pr-view helper).
json_get() {
  python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); print(d.get(sys.argv[1], ""))' "$1" 2>/dev/null || true
}

# PR argument → PR_REPO + PR_NUMBER (mirrors review-run.sh resolve_pr).
resolve_pr_arg() {
  local arg="$1"
  PR_REPO=""
  PR_NUMBER=""
  case "$arg" in
    http*)
      if [[ "$arg" =~ https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
        PR_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        PR_NUMBER="${BASH_REMATCH[3]}"
      else
        die "Cannot parse PR URL: '$arg' (expected https://host/<owner>/<repo>/pull/<num>)"
      fi
      ;;
    */*#*)
      PR_REPO="${arg%%#*}"; PR_NUMBER="${arg##*#}"
      ;;
    *#*)
      PR_REPO="$(qualify_repo_revise "${arg%%#*}")"; PR_NUMBER="${arg##*#}"
      ;;
    *[0-9]*)
      PR_NUMBER="${arg//[^0-9]/}"
      PR_REPO="$(default_repo_revise)"
      ;;
    *)
      die "Cannot interpret PR argument '$arg' (expected repo#num, URL, or number)"
      ;;
  esac
  [[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || die "Invalid PR number: '$PR_NUMBER'"
  [ -z "$PR_REPO" ] && die "Could not resolve a repo for '$arg'"
  echo "  Resolved PR: $PR_REPO#$PR_NUMBER" >&2
}

qualify_repo_revise() {
  local name="$1"
  if [[ "$name" == *"/"* ]]; then echo "$name"; return 0; fi
  local owner; owner="$(repo_owner_revise)"
  if [ -n "$owner" ]; then echo "$owner/$name"; else echo "$name"; fi
}

default_repo_revise() {
  if [ -n "${IMPLEMENTER_DEFAULT_REPO:-}" ]; then echo "$IMPLEMENTER_DEFAULT_REPO"; return 0; fi
  local url; url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"
  [ -z "$url" ] && { echo ""; return 0; }
  echo "$url" | sed -E 's#.*[:/]([^/:]+)/([^/.]+)(\.git)?#\1/\2#'
}

repo_owner_revise() {
  local r; r="$(default_repo_revise)"; echo "${r%%/*}"
}

# Fetch PR metadata (title, refs, shas, state) and GUARD that the PR is open
# and not merged — a revision can only target a live PR (else exit 2).
# NOTE: gh 2.45 `pr view --json merged` is NOT a valid field (whole call errors)
# — same family as the baseRefOid dogfood bug. Merged PRs report state=MERGED,
# so the state guard covers merged + closed without an extra field.
pr_revision_metadata() {
  local json
  json="$(gh_call pr view "$PR_NUMBER" --repo "$PR_REPO" --json \
      number,title,headRefName,baseRefName,headRefOid,state 2>/dev/null || true)"
  if [ -z "$json" ]; then
    die "gh could not fetch PR $PR_REPO#$PR_NUMBER (is gh authenticated on the host?)"
  fi
  PR_TITLE="$(printf '%s' "$json" | json_get title)"
  PR_HEAD_REF="$(printf '%s' "$json" | json_get headRefName)"
  PR_BASE_REF="$(printf '%s' "$json" | json_get baseRefName)"
  PR_HEAD_SHA="$(printf '%s' "$json" | json_get headRefOid)"
  PR_STATE="$(printf '%s' "$json" | json_get state)"
  if [ "$PR_STATE" != "OPEN" ]; then
    die "PR $PR_REPO#$PR_NUMBER is not open (state=$PR_STATE) — revision requires an open, unmerged PR."
  fi
  echo "  PR #$PR_NUMBER (open) title='$PR_TITLE' head=$PR_HEAD_REF base=$PR_BASE_REF" >&2
}

# Slug from PR title: "[factory] <slug>: …" · fall back to branch factory/<slug>/.
resolve_revision_slug() {
  local title="${1:-}" branch="${2:-}"
  PRD_SLUG=""
  if [[ "$title" =~ ^\[factory\][[:space:]]*([^:]+): ]]; then
    PRD_SLUG="${BASH_REMATCH[1]}"
  fi
  if [ -z "$PRD_SLUG" ] && [[ "$branch" =~ ^factory/([^/]+)/ ]]; then
    PRD_SLUG="${BASH_REMATCH[1]}"
  fi
  PRD_SLUG="$(echo "$PRD_SLUG" | tr -d '[:space:]')"
  if [ -z "$PRD_SLUG" ]; then
    die "Could not resolve a task slug from PR title '$title' or branch '$branch'."
  fi
  echo "  Resolved task slug: $PRD_SLUG" >&2
}

# Original impl session UUID + review session from the task PR tracking (decision 06).
resolve_impl_session() {
  local task_file="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  [ -f "$task_file" ] || die "Task file not found: $task_file (slug: $PRD_SLUG)"
  IMPL_UUID="$(grep -m1 'Raised by: implementer run ' "$task_file" \
    | sed -E 's/.*implementer run ([0-9a-f-]{36}).*/\1/' )"
  if [ -z "$IMPL_UUID" ]; then
    die "No original implementation session ('Raised by: implementer run <uuid>') on task $PRD_SLUG."
  fi
  REVIEW_SESSION="$(grep -m1 'Review: session ' "$task_file" \
    | sed -E 's/.*Review: session ([0-9a-f-]+).*/\1/' )"
  echo "  Original impl session UUID (D1, reused): $IMPL_UUID" >&2
}

# Newest docs/code-reviews/*-<slug>/ with a REQUEST_CHANGES verdict (binding spec).
resolve_review_report() {
  local base="$WORKSPACE/docs/code-reviews"
  local newest="" d
  for d in "$base"/*-"$PRD_SLUG"; do
    [ -f "$d/report.md" ] || continue
    if grep -q 'REQUEST_CHANGES' "$d/report.md"; then
      newest="$d"  # date-prefixed dirs glob in order → newest date wins
    fi
  done
  if [ -z "$newest" ]; then
    die "No REQUEST_CHANGES review report found for slug '$PRD_SLUG' in $base/ (nothing binding to fix)."
  fi
  REVIEW_DIR="$newest"
  echo "  Binding review (REQUEST_CHANGES): $REVIEW_DIR" >&2
}

# Full revision resolution: PR arg → repo/number → metadata → slug → original
# session → review. Sets PR_REPO/PR_NUMBER/PR_TITLE/PR_HEAD_REF/PRD_SLUG/
# IMPL_UUID/REVIEW_SESSION/REVIEW_DIR/PRD.
resolve_revision() {
  resolve_pr_arg "$REVISE_PR"
  pr_revision_metadata
  resolve_revision_slug "$PR_TITLE" "$PR_HEAD_REF"
  resolve_impl_session
  resolve_review_report
  PRD="$(ls "$WORKSPACE"/docs/prd-queue/*-"$PRD_SLUG.md" 2>/dev/null | head -1 || true)"
  if [ -z "$PRD" ] || [ ! -f "$PRD" ]; then
    die "No PRD found for slug '$PRD_SLUG' in docs/prd-queue/"
  fi
  echo "  PRD: $(basename "$PRD")" >&2
}

# revision_number: <n-th> revision report (1-based) for this task lineage.
revision_number() {
  local dest="$WORKSPACE/$ARCHIVES_ROOT/$(date '+%Y-%m-%d')-$PRD_SLUG"
  local n=0 f
  for f in "$dest"/revision-*.md; do
    [ -f "$f" ] && n=$((n+1))
  done
  echo $((n+1))
}

# prepare_revision_dir(): reconstruct RUN_DIR with the SAME branch worktree,
# seeded sessions/ (original session file), mounted review/, revision brief.
# No new UUID (D1) — IMPL_UUID stays the original impl session.
prepare_revision_dir() {
  local ts; ts="$(now_ts)"
  RUN_DIR="$RUNS_ROOT/$PRD_SLUG-$ts"
  WORKTREE="$RUN_DIR/worktree"
  OUTBOX="$RUN_DIR/outbox"
  SESSION_LOG="$RUN_DIR/session.jsonl"
  mkdir -p "$OUTBOX/decisions" "$RUN_DIR/sessions" "$RUN_DIR/review/decisions"
  echo "  Run dir (revision): $RUN_DIR" >&2
  echo "  Reusing original impl session UUID: $IMPL_UUID (decision 08, D1)" >&2

  local src_repo="$WORKSPACE/$TARGET_REPO"
  [ -d "$src_repo/.git" ] || die "Target repo not a git repo: $src_repo"

  # Self-contained clone in the run dir (keeps all git metadata writable).
  git clone --quiet --local "$src_repo" "$WORKTREE" 2>/dev/null \
    || git clone --quiet "$src_repo" "$WORKTREE"
  # Point origin at the REAL remote (clone --local sets it to the local path).
  local real_url
  real_url="$(git -C "$src_repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$real_url" ]; then
    git -C "$WORKTREE" remote set-url origin "$real_url"
  fi
  # Check out the SAME branch the PR is on, so the fix rides on top of it.
  git -C "$WORKTREE" fetch --quiet origin "$PR_HEAD_REF" 2>/dev/null \
    || git -C "$WORKTREE" fetch --quiet origin >/dev/null 2>&1 || true
  git -C "$WORKTREE" checkout -q -B "$PR_HEAD_REF" "origin/$PR_HEAD_REF" 2>/dev/null \
    || git -C "$WORKTREE" checkout -q -B "$PR_HEAD_REF" "$PR_HEAD_REF"
  git -C "$WORKTREE" config user.name "${IMPL_GIT_NAME:-factory}"
  git -C "$WORKTREE" config user.email "${IMPL_GIT_EMAIL:-factory@ak47.local}"
  WORKTREE_BRANCH="$PR_HEAD_REF"
  echo "  Worktree at SAME branch: $WORKTREE (branch $WORKTREE_BRANCH)" >&2

  # Seed sessions/ with the original session file (pi-native naming, D6) so
  # --continue in the container resumes the original conversation.
  local sess_src="$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl"
  if [ -f "$sess_src" ]; then
    cp "$sess_src" "$RUN_DIR/sessions/${ts}_${IMPL_UUID}.jsonl"
    echo "  Seeded sessions/ with original session: ${ts}_${IMPL_UUID}.jsonl" >&2
  else
    echo "  WARN: original session file missing at $sess_src — continuing without seed." >&2
  fi

  # Mount the review report + decisions as the binding fix spec.
  cp "$REVIEW_DIR/report.md" "$RUN_DIR/review/report.md"
  if [ -d "$REVIEW_DIR/decisions" ]; then
    cp "$REVIEW_DIR/decisions/"*.md "$RUN_DIR/review/decisions/" 2>/dev/null || true
  fi
  echo "  Mounted review report+decisions → review/" >&2

  REVISION_N="$(revision_number)"
  write_revision_brief "$ts"
}

# write_revision_brief(): revision variant of the brief (binding-authority).
write_revision_brief() {
  local ts="$1"
  cat > "$RUN_DIR/brief.md" <<EOF
# Implementer Revision Brief

- **PR**: $PR_REPO#$PR_NUMBER (same branch: $WORKTREE_BRANCH)
- **Task slug**: $PRD_SLUG
- **PRD path** (read-only; also below): ${PRD#/workspace/}
- **Impl session UUID** (reused from the original run, decision 08): $IMPL_UUID
- **Original review (BINDING authority)**: /sandbox/review/report.md + /sandbox/review/decisions/
- **Worktree path** (same branch, read-write): /sandbox/worktree
- **Outbox path** (write results here): /sandbox/outbox

## Rules (binding)

1. Fix EXACTLY what the review findings scope — no more, no less. No scope expansion.
2. WHERE THE REVIEW FINDINGS CONFLICT WITH YOUR EARLIER REASONING, THE FINDINGS WIN.
   The review report + decisions are higher-priority authority than your prior reasoning.
3. Resume your original implementation session context (continuity) — do NOT
   restart from scratch, do NOT re-litigate findings.
4. Do NOT run any git commands (the host owns git). Do NOT change the task
   lifecycle — the task stays in-review through the re-review.
5. Do NOT write secrets, keys, or GitHub credentials anywhere.

## Verification

See the PRD \`## Testing decisions\` for the acceptance commands. Run them inside the worktree as the PRD specifies.
- State evidence for each story (what you changed and how it is verified).

## Completion

Write /sandbox/outbox/report.md (per-story done/not-done + evidence +
verification results + UAT hand-off list) and any emerged decisions to
/sandbox/outbox/decisions/NN-<slug>.md (structured decision format), then exit 0.
On partial failure, still write the report and exit 1.
EOF
  echo "  Revision brief written: $RUN_DIR/brief.md" >&2
}

# archive_revision(): one implementation dir per lineage (D5) — the revision
# report lands NEXT TO v1 report.md as revision-<n>-report.md.
archive_revision() {
  local ts; ts="$(date '+%Y-%m-%d')"
  local dest="$WORKSPACE/$ARCHIVES_ROOT/$ts-$PRD_SLUG"
  mkdir -p "$dest/decisions"
  if [ -f "$OUTBOX/report.md" ]; then
    cp "$OUTBOX/report.md" "$dest/revision-${REVISION_N}-report.md"
  fi
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$dest/decisions/" 2>/dev/null || true
  fi
  cp "$RUN_DIR/brief.md" "$dest/brief.md" 2>/dev/null || true
  echo "  Archived revision ${REVISION_N} → $dest/revision-${REVISION_N}-report.md" >&2
  ARCHIVE_DEST="$dest"
}

# deliver_revision(): commit the fix on the SAME branch, push origin/<branch>
# (updates PR #N), post a PR comment — NO gh pr create (D4), NO merge (D4),
# NO task transition (D3). Appends the decision-06 `Revised:` row.
deliver_revision() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would commit+push branch $WORKTREE_BRANCH, post PR comment, and append Revised row" >&2
    return 0
  fi

  local head_sha
  # Host authors the commit from the implementer's files (the implementer never
  # touches git).
  git -C "$WORKTREE" add -A
  if ! git -C "$WORKTREE" diff --cached --quiet; then
    if ! git -C "$WORKTREE" -c user.name="${IMPL_GIT_NAME:-factory}" \
          -c user.email="${IMPL_GIT_EMAIL:-factory@ak47.local}" commit -q \
          -m "implementer($PRD_SLUG): revision ${REVISION_N} [factory] run $IMPL_UUID"; then
      echo "  ERROR: could not commit revision fix." >&2
      return 2
    fi
  else
    echo "  [no-op] revision made no changes beyond the PR head — delivering as-is." >&2
  fi
  head_sha="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || echo '?')"

  # Push the SAME branch — a normal fast-forward push (the branch exists on
  # origin), updating the open PR. No gh pr create.
  git -C "$WORKTREE" push -u origin "$WORKTREE_BRANCH"
  echo "  Pushed revision to $WORKTREE_BRANCH (updates PR #$PR_NUMBER)" >&2

  # PR comment noting the revision.
  local body_file="$RUN_DIR/revision-comment.md"
  {
    echo "## Implementer Revision ($PRD_SLUG)"
    echo ""
    echo "Addressed review findings from the original implementer run (session $IMPL_UUID)."
    echo ""
    if [ -f "$ARCHIVE_DEST/revision-${REVISION_N}-report.md" ]; then
      cat "$ARCHIVE_DEST/revision-${REVISION_N}-report.md"
    fi
  } > "$body_file"
  if command -v "${IMPLEMENTER_GH_BIN:-gh}" >/dev/null 2>&1; then
    gh_call pr comment "$PR_NUMBER" --repo "$PR_REPO" --body-file "$body_file"
    echo "  Posted revision comment to $PR_REPO#$PR_NUMBER." >&2
  else
    echo "  [warn] gh not available; revision PR comment skipped." >&2
  fi

  # Decision 06: append the `Revised:` row (append-only history).
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/bin/lib-pr-tracking.sh"
  local task="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  local now; now="$(date '+%Y-%m-%d %H:%M')"
  if pr_tracking_ensure "$task" && ! pr_tracking_has "$task" "Revised: $head_sha"; then
    pr_tracking_add "$task" \
      "- Revised: $head_sha ($now, impl session $IMPL_UUID, addressing review ${REVIEW_SESSION:-?})"
    ( cd "$WORKSPACE" && git add "docs/tasks/$PRD_SLUG.md" 2>/dev/null || true
      git diff --cached --quiet || git commit -q -m "task($PRD_SLUG): record revision ${REVISION_N} (tracking)" )
  fi
  echo "  Task PR tracking: Revised row recorded on docs/tasks/$PRD_SLUG.md" >&2
}

# finalize_revision_session(): the revision extends the SAME <orig-uuid>
# session file (D1) — the durable copy is refreshed from the streamed transcript
# / pi-native seed, and outbox decisions are mirrored into the knowledge dir.
finalize_revision_session() {
  local sess="$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl"
  mkdir -p "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/decisions"
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/decisions/" 2>/dev/null || true
    local idx="$WORKSPACE/docs/knowledge/index.md"
    if ! grep -q "^### $PROJECT" "$idx" 2>/dev/null; then
      printf '\n### %s\n' "$PROJECT" >> "$idx"
    fi
    local d
    for d in "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"/decisions/*.md; do
      [ -f "$d" ] || continue
      local base; base="$(basename "$d")"
      local title; title="$(echo "$base" | sed -E 's/^[0-9]+-//; s/\.md$//; s/-/ /g')"
      if ! grep -Fq "sessions/$IMPL_UUID/decisions/$base" "$idx"; then
        python3 - "$idx" "$PROJECT" "$title" "$IMPL_UUID" "$base" <<'PYEOF'
import sys
path, proj, title, uuid, base = sys.argv[1:6]
with open(path) as f:
    lines = f.read().split('\n')
out = []
inserted = False
for line in lines:
    out.append(line)
    if line.strip() == f'### {proj}' and not inserted:
        out.append(f'- [{title}](sessions/{uuid}/decisions/{base})')
        inserted = True
with open(path, 'w') as f:
    f.write('\n'.join(out) + '\n')
PYEOF
      fi
    done
    if [ -f "$WORKSPACE/bin/sort-knowledge-index.py" ]; then
      python3 "$WORKSPACE/bin/sort-knowledge-index.py" >/dev/null 2>&1 || true
    fi
  fi
}

# ─── main_revise(): full --revise flow ─────────────────────────────────────
# Sets REVISION_MODE already true (arg parsing). Never transitions the task
# (D3), never mints a new UUID (D1), never calls push_and_pr (D4).
main_revise() {
  echo "=== implementer-run.sh (revision mode) ==="
  echo "  dry-run: $DRY_RUN | revising PR: $REVISE_PR"
  resolve_revision
  resolve_repo
  prepare_revision_dir

  # ── Run the container with respawn (cattle) ──────────────────────────────
  local_result=1
  attempt=1
  while [ $attempt -le "$RESPAWN_CAP" ]; do
    if run_container "$attempt"; then
      local_result=0
      break
    fi
    if [ $attempt -lt "$RESPAWN_CAP" ]; then
      echo "  Respawn: attempt $attempt failed; starting fresh container against same run dir." >&2
    fi
    attempt=$((attempt+1))
  done

  if [ "$local_result" -eq 0 ]; then
    echo "=== Implementer revision success — archiving + delivering on the same PR ===" >&2
    archive_revision
    finalize_revision_session
    if [ "$DRY_RUN" = true ]; then
      deliver_revision  # prints the dry-run simulation line
      echo "  [dry-run] would commit+push workspace root (archive, index, task-file session link)" >&2
    else
      deliver_revision
      # Persist the archive/index/session/task on the workspace root.
      ( cd "$WORKSPACE" && git add "$ARCHIVES_ROOT" "docs/knowledge/sessions/$IMPL_UUID" \
          docs/knowledge/index.md docs/tasks/$PRD_SLUG.md docs/tasks.txt 2>/dev/null || true
        git diff --cached --quiet || git commit -q -m "implementer($PRD_SLUG): archive revision ${REVISION_N} [impl $IMPL_UUID]" )
    fi
    stop_container
    if [ "$DRY_RUN" != true ] && [ "${IMPL_CLEANUP:-$CLEANUP_ENABLED}" != "false" ]; then
      cleanup_run_dir
    fi
    echo "Done (exit 0)."
    exit 0
  else
    fail_run "revision container/implementer failed after ${RESPAWN_CAP} attempts"
  fi
}

# ─── main ──────────────────────────────────────────────────────────────────
# Guard: when sourced by a test harness, do not auto-run main.
if [ "${IMPLEMENTER_RUN_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

echo "=== implementer-run.sh ==="
echo "  dry-run: $DRY_RUN | mode: $([ "$REVISION_MODE" = true ] && echo "--revise $REVISE_PR" || echo "${MODE_FLAG:---task $TASK}")"

# Revision path (decision 08): resumes the original impl session on the same
# branch; never transitions the task, never mints a new UUID, never raises a PR.
if [ "$REVISION_MODE" = true ]; then
  main_revise
  exit 0
fi

resolve_prd
resolve_repo
prepare_run_dir
# Multi-repo: prepare the additional app-repo worktrees (the root worktree
# already exists). All worktrees live under RUN_DIR/worktrees/<key>/ and are
# visible to the single container via the -v $RUN_DIR:/sandbox mount.
if [ "${#REPO_KEYS[@]}" -gt 1 ]; then
  prepare_run_dirs
fi
transition "in-progress"
write_session_header

# ── Run the container with respawn (cattle) ────────────────────────────────
local_result=1
attempt=1
while [ $attempt -le "$RESPAWN_CAP" ]; do
  if run_container "$attempt"; then
    local_result=0
    break
  fi
  if [ $attempt -lt "$RESPAWN_CAP" ]; then
    echo "  Respawn: attempt $attempt failed; starting fresh container against same run dir." >&2
  fi
  attempt=$((attempt+1))
done

# Finalize the knowledge copy of the session with the full streamed transcript
# (the startup header above is just a stub). The pi-native session also lives on
# the host mount under the run dir; prefer it, falling back to the tee transcript.
finalize_session_copy() {
  local sess="$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl"
  # pi names its files  <ts>_<session-uuid>.jsonl under the session-dir mount.
  local native=""
  # Guard the glob: on a failed run there may be no session file, and under
  # `set -o pipefail` a non-matching `ls -t ... *.jsonl | head -1` makes the
  # command-substitution assignment return non-zero, which `set -e` turns into
  # a silent exit-2 abort BEFORE fail_run runs (no FAILED msg, no report).
  # compgen only runs `ls` when the glob actually matches.
  if compgen -G "$RUN_DIR/sessions/*.jsonl" >/dev/null 2>&1; then
    native="$(ls -t "$RUN_DIR"/sessions/*.jsonl 2>/dev/null | head -1)"
  fi
  if [ -n "$native" ] && [ -s "$native" ]; then
    cp "$native" "$sess"
  elif [ -s "$SESSION_LOG" ]; then
    cp "$SESSION_LOG" "$sess"
  fi
  # GH013 guard: this transcript is committed to the repo (tracking commit).
  # Sanitize the committed copy IN-PLACE so GitHub push protection never
  # blocks it; the RAW native session stays in RUN_DIR/sessions/ for the
  # private trace bundle. If sanitize is incomplete, warn — never abort.
  if [ -s "$sess" ]; then
    if bash "$WORKSPACE/bin/sanitize-session.sh" "$sess" >/dev/null 2>&1; then
      :
    else
      echo "  WARN: session sanitize incomplete (rc=$?) — add patterns to bin/sanitize-session.sh" >&2
    fi
  fi
}
finalize_session_copy

if [ "$local_result" -eq 0 ]; then
  echo "=== Implementer success — archiving + delivering ===" >&2
  archive
  append_decisions_to_index
  # Link the impl session on the task file (driver-side via transition tooling).
  if [ "$DRY_RUN" != true ]; then
    transition "in-progress"
  fi
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would commit+push workspace root, push branch(es), and raise PR(s)" >&2
    write_run_manifest; print_manifest
  else
    # Commit + push the workspace root (archive, index, task-file session link).
    ( cd "$WORKSPACE" && git add "$ARCHIVES_ROOT" docs/knowledge/sessions/$IMPL_UUID \
        docs/knowledge/index.md docs/tasks/$PRD_SLUG.md docs/tasks.txt 2>/dev/null || true
      git diff --cached --quiet || git commit -m "implementer($PRD_SLUG): archive run report + decisions [impl $IMPL_UUID]" )
    # Delivery is load-bearing: a failed branch push or PR creation must route
    # to the failure path (revert task to prd-ready, archive partial report,
    # exit 1) — never be swallowed into a false "Done (exit 0)". The guard must
    # be explicit: under `set -e` an unguarded failing call would abort the
    # script before fail_run runs.
    if [ "${#REPO_KEYS[@]}" -eq 1 ] && [ "${REPO_KEYS[0]}" != "workspace" ]; then
      # Legacy single app-repo task: keep the original push_and_pr flow
      # (backward compatible with every existing PRD).
      if ! push_and_pr; then
        fail_run "delivery failed: branch push or PR creation"
      fi
      write_run_manifest; print_manifest
    else
      # Root (Shape B collapse) or multi-repo (N code PRs): repo-set delivery
      # enforces the A/B invariant + docs-only tripwire + run manifest.
      if ! deliver_repo_set; then
        fail_run "delivery failed: per-repo push/PR, invariant, or tripwire"
      fi
    fi
  fi
  # The run is delivered: the container is no longer needed, and the host only
  # keeps the durable artifacts (outbox, session evidence, brief, worktree).
  stop_container
  if [ "$DRY_RUN" != true ] && [ "${IMPL_CLEANUP:-$CLEANUP_ENABLED}" != "false" ]; then
    cleanup_run_dir
  fi
  echo "Done (exit 0)."
  exit 0
else
  fail_run "container/implementer failed after ${RESPAWN_CAP} attempts"
fi
