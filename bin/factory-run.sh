#!/usr/bin/env bash
# ============================================================================
# factory-run.sh — one-command implement → review chain (thin orchestrator).
#
# Convenience wrapper that runs the two manual-trigger drivers back-to-back:
#   1. bin/implementer-run.sh  (raises the PR, labels factory:needs-review)
#   2. bin/review-run.sh       (reviews the raised PR, posts verdict, transitions)
#
# Authority-split guarantees (decisions 01/05/07):
#   * This script NEVER merges. There is no merge path here by design — after
#     the chain, the human does UAT and runs bin/merge-pr.sh themselves.
#   * A UAT banner + prompt sits between implement and review (unless --yes):
#     the human inspects the PR before the autonomous review runs.
#   * Master is never pushed by this chain (decision 07: merge-pr.sh is the
#     only master-pusher). Tracking commits accumulate locally and go up with
#     the merge.
#
# Usage:
#   bin/factory-run.sh [--task <slug>] [--yes] [--implement-only]
#                      [--review <pr>] [--dry-run] [--headless]
#   --task <slug>     Task to implement (passed to implementer-run; default: --pick)
#   --yes             Skip the UAT prompt (still never merges)
#   --implement-only  Implement only — do NOT run the review
#   --review <pr>     Review-selection override (default: the PR just raised,
#                     resolved from the task's decision-06 PR tracking row;
#                     falls back to --pick)
#   --dry-run         Pass --dry-run to the implementer; review is skipped
#                     (nothing to review — no PR exists in dry-run)
#   --headless        Decision 04: fully autonomous loop. No UAT gate. On
#                     REQUEST_CHANGES, run implementer-run.sh --revise <pr> and
#                     re-review up to REVISION_CAP (default 3); stop at APPROVE;
#                     on cap exhaustion exit non-zero with the last report surfaced.
#
# Exit codes:
#   0  Success (implement + review done, or implement-only, or deferred at UAT)
#      or headless loop ended at APPROVE
#   1  Implementer failed (review skipped; task reverted, no PR)
#   2  Reviewer failed (PR left open; re-run bin/review-run.sh --pick later)
#   3  Usage error
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test seams: FACTORY_WORKSPACE (fixture workspace), FA_RUN_IMPLEMENTER /
# FA_RUN_REVIEWER (stub drivers), FA_LOG (stub call log).
WORKSPACE="${FACTORY_WORKSPACE:-$SCRIPT_DIR}"
IMPLEMENTER="${FA_RUN_IMPLEMENTER:-$SCRIPT_DIR/bin/implementer-run.sh}"
REVIEWER="${FA_RUN_REVIEWER:-$SCRIPT_DIR/bin/review-run.sh}"

usage() {
  cat <<'EOF'
Usage:
  bin/factory-run.sh [--task <slug>] [--yes] [--implement-only]
                     [--review <pr>] [--dry-run]

  --task <slug>     Task to implement (passed to implementer-run; default: --pick)
  --yes             Skip the UAT prompt (still never merges)
  --implement-only  Implement only — do NOT run the review
  --review <pr>     Review-selection override (default: the PR just raised,
                    resolved from the task's decision-06 PR tracking row;
                    falls back to --pick)
  --dry-run         Pass --dry-run to the implementer; review is skipped
                    (nothing to review — no PR exists in dry-run)
  --headless        Decision 04: fully autonomous loop. No UAT gate. On
                    REQUEST_CHANGES, run implementer-run.sh --revise <pr> and
                    re-review up to REVISION_CAP (default 3); stop at APPROVE;
                    on cap exhaustion exit non-zero with the last report surfaced.

Exit codes: 0 success/deferred/approved · 1 implementer failed · 2 reviewer failed · 3 usage
EOF
}

TASK_ARG=""; YES=false; IMPL_ONLY=false; REVIEW_OVERRIDE=""; DRY_RUN=false; HEADLESS=false
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK_ARG="$2"; shift 2 ;;
    --yes) YES=true; shift ;;
    --implement-only) IMPL_ONLY=true; shift ;;
    --review) REVIEW_OVERRIDE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --headless) HEADLESS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 3 ;;
  esac
done

if [ ! -x "$IMPLEMENTER" ]; then echo "ERROR: implementer driver not found: $IMPLEMENTER" >&2; exit 3; fi
if [ ! -x "$REVIEWER" ]; then echo "ERROR: reviewer driver not found: $REVIEWER" >&2; exit 3; fi

# ─── Multi-repo runtime config (mirrors the drivers) ───────────────────────
# Runs root used to locate the implementer's run manifest (BK_MANIFEST default,
# story 7 / review B-3) and the reviewer's run-dir verdicts (story 9 / J2).
# Test seam: FA_RUNS_ROOT; reads config/implementer.json `.runs_root` when past.
FA_RUNS_ROOT="${FA_RUNS_ROOT:-$HOME/.factory/runs}"
CONFIG_FILE="${FA_CONFIG:-$WORKSPACE/config/implementer.json}"
if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  FR_R="$(jq -r '.runs_root // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  [ -n "$FR_R" ] && FA_RUNS_ROOT="${FR_R/#\~/$HOME}"
fi

# factory_manifest <slug>: path of the implementer run's manifest.json (the most
# recent run dir for the slug that has one). Empty when none exists (legacy
# single-repo / no manifest).
factory_manifest() {
  local slug="$1" d
  for d in $(ls -dt "$FA_RUNS_ROOT/$slug"-* 2>/dev/null); do
    [ -f "$d/manifest.json" ] && { echo "$d/manifest.json"; return 0; }
  done
  echo ""
}

# review_run_dir <slug>: the reviewer run dir holding a run-dir verdict
# (reports/verdict.txt) — the loop-end verdict read-back source (J2).
review_run_dir() {
  local slug="$1" d
  for d in $(ls -dt "$FA_RUNS_ROOT/$slug"-* 2>/dev/null); do
    [ -f "$d/reports/verdict.txt" ] && { echo "$d"; return 0; }
  done
  echo ""
}


# ─── Credential convenience ───────────────────────────────────────────────
# The drivers read OPENROUTER_API_KEY from their own env (env_allowlist).
# If it's not already exported, load it from pi's auth.json (matches the
# manual fix that unblocked the first dogfood run).
if [ -z "${OPENROUTER_API_KEY:-}" ] && [ -f "$HOME/.pi/agent/auth.json" ]; then
  KEY="$(jq -r '.openrouter.key // empty' "$HOME/.pi/agent/auth.json" 2>/dev/null || true)"
  if [ -n "$KEY" ]; then
    export OPENROUTER_API_KEY="$KEY"
    echo "  OPENROUTER_API_KEY loaded from ~/.pi/agent/auth.json" >&2
  else
    echo "  WARN: OPENROUTER_API_KEY unset and auth.json has no .openrouter.key" >&2
  fi
fi

RUN_LOG="$(mktemp)"; REV_LOG="$(mktemp)"
trap 'rm -f "$RUN_LOG" "$REV_LOG"' EXIT

# Headless revision cap (decision 04). Env-configurable, default 3.
REVISION_CAP="${REVISION_CAP:-3}"

# ─── Multi-repo bookkeeping (PRD: multi-repo delivery bookkeeping PRs) ─────
# Shape A (workspace root NOT touched) gets exactly one docs-only bookkeeping PR
# on the workspace root, raised at loop end (success OR failure). Shape B
# (root touched) gets NO separate bookkeeping PR — the root code PR already
# carries code + bookkeeping commits (implementer-run.sh). The A/B invariant is
# therefore preserved by construction.
#
# raise_bookkeeping_pr <task> <root-pr-or-empty>: create a scratch clone of the
# root, copy the run's docs artifacts (archived report/decisions/manifest) under
# docs/, enforce the docs-only tripwire, push a `factory/<slug>/bookkeeping/<ts>`
# branch and raise a `factory:bookkeeping` PR. Mirrors the manifest schema into
# the PR body. Returns the PR url (or '' when gh/no-docs).
FACTORY_GH_BIN="${FACTORY_GH_BIN:-gh}"
raise_bookkeeping_pr() {
  local task="$1"
  local ts; ts="$(date '+%Y%m%d-%H%M%S')"
  local branch="factory/$task/bookkeeping/$ts"
  local bk_dir; bk_dir="$(mktemp -d)"
  git clone --quiet --local "$WORKSPACE" "$bk_dir/root" 2>/dev/null \
    || git clone --quiet "$WORKSPACE" "$bk_dir/root" || true
  git -C "$bk_dir/root" checkout -q -b "$branch" origin/master 2>/dev/null \
    || git -C "$bk_dir/root" checkout -q -b "$branch" master 2>/dev/null || true
  git -C "$bk_dir/root" config user.name "${IMPL_GIT_NAME:-factory}"
  git -C "$bk_dir/root" config user.email "${IMPL_GIT_EMAIL:-factory@ak47.local}"
  # B-5: the scratch clone's origin points at the LOCAL $WORKSPACE (clone --local
  # sets it to the source path); point it at the real GitHub remote so the
  # bookkeeping branch + PR actually reach GitHub (contrast: implementer-run.sh
  # resets the clone's origin the same way via `remote set-url origin`).
  local real_url; real_url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"
  if [ -n "$real_url" ]; then git -C "$bk_dir/root" remote set-url origin "$real_url"; fi
  # Copy the run's durable docs artifacts under docs/implementation (docs-only).
  mkdir -p "$bk_dir/root/docs/implementations/$(date '+%Y-%m-%d')-$task"
  if [ -f "$WORKSPACE/docs/implementations/$(date '+%Y-%m-%d')-$task/report.md" ]; then
    cp "$WORKSPACE/docs/implementations/$(date '+%Y-%m-%d')-$task/report.md" \
       "$bk_dir/root/docs/implementations/$(date '+%Y-%m-%d')-$task/" 2>/dev/null || true
  fi
  if [ -f "$BK_MANIFEST" ]; then
    cp "$BK_MANIFEST" "$bk_dir/root/docs/implementations/$(date '+%Y-%m-%d')-$task/manifest.json" 2>/dev/null || true
  fi
  git -C "$bk_dir/root" add -A docs/ 2>/dev/null || true
  if git -C "$bk_dir/root" diff --cached --quiet; then
    echo "  (bookkeeping) no docs artifacts to commit — skipping bookkeeping PR." >&2
    return 0
  fi
  # Docs-only tripwire (F4 / story 6).
  local bad=0 f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in docs/*) : ;; *) echo "  TRIPWIRE: bookkeeping PR touches non-docs path: $f" >&2; bad=1 ;; esac
  done <<< "$(git -C "$bk_dir/root" diff --cached --name-only)"
  if [ "$bad" -ne 0 ]; then
    echo "  FAILED: bookkeeping PR diff touches code paths (tripwire) — run aborted." >&2
    return 1
  fi
  git -C "$bk_dir/root" commit -q -m "factory($task): bookkeeping (docs only)" \
    || { echo "  (bookkeeping) commit failed." >&2; return 1; }
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would push $branch and raise factory:bookkeeping PR on the root" >&2
    return 0
  fi
  if ! git -C "$bk_dir/root" push -u origin "$branch"; then
    echo "  ERROR: bookkeeping branch push failed ($branch)." >&2
    return 1
  fi
  if ! command -v "$FACTORY_GH_BIN" >/dev/null 2>&1; then
    echo "  (bookkeeping) gh not available — bookkeeping branch pushed, PR skipped." >&2
    return 0
  fi
  local body="$bk_dir/body.md"
  { echo "## Factory Bookkeeping ($task)"; echo ""; echo "Docs-only delivery bookkeeping."; echo "";
    if [ -f "$BK_MANIFEST" ]; then echo "### Run manifest"; echo '```json'; cat "$BK_MANIFEST"; echo '```'; fi
  } > "$body"
  "$FACTORY_GH_BIN" label create "factory:bookkeeping" --repo "${FACTORY_ROOT_REPO:-ak47-arch/workspace}" --force >/dev/null 2>&1 || true
  local url
  url="$("$FACTORY_GH_BIN" pr create --repo "${FACTORY_ROOT_REPO:-ak47-arch/workspace}" \
      --base master --head "$branch" --title "[factory] $task: bookkeeping" \
      --body-file "$body" --label "factory:bookkeeping" 2>/dev/null)"
  if [ -z "$url" ]; then
    # F3 fail-loud (review B-5): a failed `gh pr create` must NOT look like
    # success. The docs branch is already pushed — surface the failure clearly.
    echo "  FAILED: bookkeeping gh pr create returned no URL (branch $branch was pushed; no PR raised). run aborted." >&2
    return 1
  fi
  echo "  Bookkeeping PR raised: $url" >&2
  BK_PR="$url"
  # Mirror the bookkeeping PR into the run manifest so the loop-end A/B XOR
  # (and the bookkeeping PR row in the manifest) reflect reality (story 7).
  if [ -n "${BK_MANIFEST:-}" ] && [ -f "$BK_MANIFEST" ]; then
    local bk_num; bk_num="$(printf '%s' "$url" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
    set_manifest_bookkeeping_pr "$BK_MANIFEST" "$bk_num"
  fi
  return 0
}

# set_manifest_bookkeeping_pr <manifest> <pr-number>: patch the run manifest's
# bookkeeping_pr field (story 7 mirroring + loop-end invariant input).
set_manifest_bookkeeping_pr() {
  local mf="$1" pr="$2"
  [ -f "$mf" ] || return 0
  python3 - "$mf" "$pr" <<'PYEOF' || true
import json, sys
mf, pr = sys.argv[1], sys.argv[2]
try:
    with open(mf) as f: d = json.load(f)
except Exception:
    sys.exit(0)
d["bookkeeping_pr"] = int(pr) if str(pr).isdigit() else None
with open(mf, "w") as f:
    json.dump(d, f, indent=2)
PYEOF
}

# print_manifest: surface the run manifest at loop end (story 7).
print_manifest() {
  [ -f "$BK_MANIFEST" ] || { echo "  [manifest] none written" >&2; return 0; }
  echo "  ── Run manifest ($BK_MANIFEST) ──" >&2
  cat "$BK_MANIFEST" >&2
}

# manifest_root_code_pr <manifest>: the root code PR number if the run manifest
# declares a touched root (Shape B). Empty for Shape A (root not touched).
manifest_root_code_pr() {
  local mf="$1"
  [ -f "$mf" ] || { echo ""; return 0; }
  python3 -c 'import json
mf=sys.argv[1]
try:
    d=json.load(open(mf))
except Exception:
    print(""); raise SystemExit
print(d.get("root_code_pr") or "")' "$mf" 2>/dev/null || echo ""
}

# finish_bookkeeping: raise the Shape-A bookkeeping PR + print the manifest at
# loop end (success or failure). The manifest seam BK_MANIFEST defaults to the
# implementer's run manifest (review B-3): a real multi-repo delivery writes
# RUN_DIR/manifest.json, so a live run raises the bookkeeping PR without any
# external env wiring. Shape B (root touched) skips the separate bookkeeping PR
# — the root code PR already carried code + bookkeeping commits. Failures
# propagate (F3 fail-loud). No-op when no manifest exists (legacy flows).
finish_bookkeeping() {
  local slug="${TASK_ARG:-$SLUG}"
  [ -n "$slug" ] || return 0
  if [ -z "${BK_MANIFEST:-}" ]; then
    BK_MANIFEST="$(factory_manifest "$slug")"
    if [ -n "$BK_MANIFEST" ]; then
      echo "  [bookkeeping] BK_MANIFEST defaulted to $BK_MANIFEST" >&2
    fi
  fi
  [ -n "$BK_MANIFEST" ] || return 0
  # Shape B (root in set): the root code PR already carries the bookkeeping
  # commits — a separate bookkeeping PR would violate the A/B invariant.
  local rcp
  rcp="$(manifest_root_code_pr "$BK_MANIFEST")"
  if [ -n "$rcp" ]; then
    echo "  (bookkeeping) Shape B: root code PR #$rcp already carries bookkeeping — no separate bookkeeping PR." >&2
    print_manifest
    return 0
  fi
  raise_bookkeeping_pr "$slug" || return 1
  print_manifest
}

# assert_loop_end_invariant <manifest>: the PRD's "after loop end" re-assert of
# the full A/B XOR, where both sides exist (root code PR vs bookkeeping PR).
# Fails loud if a legitimate Shape is violated (e.g. a Shape A task whose
# bookkeeping PR silently failed to raise).
assert_loop_end_invariant() {
  local mf="$1"
  [ -f "$mf" ] || { echo "  [invariant] no run manifest ($mf) to assert loop-end — skipped." >&2; return 0; }
  local root_code bk
  root_code="$(python3 -c 'import json;print(json.load(open("'$mf'"))["root_code_pr"] or "")' 2>/dev/null || true)"
  bk="$(python3 -c 'import json;print(json.load(open("'$mf'"))["bookkeeping_pr"] or "")' 2>/dev/null || true)"
  if { [ -n "$root_code" ] && [ -z "$bk" ]; } \
     || { [ -z "$root_code" ] && [ -n "$bk" ]; }; then
    echo "  ✓ loop-end delivery invariant holds (root_code_pr=${root_code:-none} bookkeeping_pr=${bk:-none})" >&2
    return 0
  fi
  echo "  FAILED: loop-end delivery invariant violated — root_code_pr=${root_code:-none} bookkeeping_pr=${bk:-none} (manifest $mf)." >&2
  return 1
}

# pickup_gate (story 8): skip this task if an open `[factory] <slug>` PR already
# exists in a declared repo (no re-implementation while in flight). No-op unless
# a gh binary + a repos seam are provided (tests / live GitHub).
# Declared repos come from the PRD **Repos:** header, defaulting to the root.
pickup_gate() {
  local slug="${TASK_ARG:-}"
  [ -n "$slug" ] || return 0
  command -v "$FACTORY_GH_BIN" >/dev/null 2>&1 || return 0
  if [ -z "${FACTORY_REPOS:-}" ]; then
    # Self-resolve the declared repos from the PRD **Repos:** header against the
    # local checkouts' GitHub origins (review B-2), so the gate is LIVE without
    # any env seam, in CI and locally. Defaults to the root repo.
    FACTORY_REPOS="$(gate_repos_for "$slug")"
    echo "  (pickup gate) FACTORY_REPOS resolved: $FACTORY_REPOS" >&2
  fi
  [ -n "$FACTORY_REPOS" ] || return 0
  local repo
  for repo in ${FACTORY_REPOS}; do
    local count
    count="$("$FACTORY_GH_BIN" pr list --repo "$repo" --search "\"[factory] $slug\"" --state open --json number 2>/dev/null \
      | python3 -c 'import sys,json
print(len(json.loads(sys.stdin.read() or "[]")))' 2>/dev/null || echo 0)"
    if [ "$count" -gt 0 ] 2>/dev/null; then
      echo "  SKIP: task $slug already has an open [factory] PR in $repo — not re-implementing (pickup gate)." >&2
      exit 0
    fi
  done
  return 0
}

# gate_repos_for <slug>: GitHub owner/repo slugs for the PRD **Repos:** header
# (default: the root repo). Mirrors implementer's repo-key→gh-slug derivation.
gate_repos_for() {
  local slug="$1" prd dir id repos="" url
  prd="$(ls "$WORKSPACE"/docs/prd-queue/*"-$slug.md" 2>/dev/null | head -1 || true)"
  local ids=()
  if [ -n "$prd" ] && [ -f "$prd" ]; then
    local line
    line="$(grep -m1 '^\*\*Repos\*\*:' "$prd" 2>/dev/null | sed 's/^\*\*Repos\*\*: *//' || true)"
    if [ -n "$line" ]; then
      while IFS= read -r id; do id="$(echo "$id" | tr -d ' \`')"; [ -n "$id" ] && ids+=("$id"); done \
        <<< "$(printf '%s\n' "$line" | tr ',' '\n')"
    fi
  fi
  if [ "${#ids[@]}" -eq 0 ]; then
    repos="${FACTORY_ROOT_REPO:-}"
    [ -n "$repos" ] || repos="$(gh_owner_repo "$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)")"
    echo "$repos"
    return 0
  fi
  for id in "${ids[@]}"; do
    case "$id" in .|workspace) dir="." ;; *) dir="$id" ;; esac
    url="$(git -C "$WORKSPACE/$dir" remote get-url origin 2>/dev/null || true)"
    local r; r="$(gh_owner_repo "$url")"
    [ -n "$r" ] && repos="$repos $r"
  done
  repos="$(echo "$repos" | xargs)"
  [ -n "$repos" ] || repos="${FACTORY_ROOT_REPO:-ak47-arch/workspace}"
  echo "$repos"
}

# gh_owner_repo <url>: owner/repo from a git remote URL (git@github.com:o/r.git or
# https://github.com/o/r.git), else ''.
gh_owner_repo() {
  local u="$1"
  [ -n "$u" ] || { echo ""; return 0; }
  echo "$u" | sed -E 's#.*github\.com[:/]([^/]+/[^/]+)(\.git)?$#\1#'
}

# ─── Stage 1: implement ───────────────────────────────────────────────────
echo ""
echo "── Stage 1: implementer ──"
IMPL_ARGS=()
if [ -n "$TASK_ARG" ]; then IMPL_ARGS+=(--task "$TASK_ARG"); else IMPL_ARGS+=(--pick); fi
[ "$DRY_RUN" = true ] && IMPL_ARGS+=(--dry-run)
# Pickup gate (story 8): skip a task that already has an open [factory] <slug>
# PR in any declared repo — no re-implementation while in flight. No-op unless
# FACTORY_GH_BIN + FACTORY_REPOS are provided (tests / live GitHub).
pickup_gate
set +e
"$IMPLEMENTER" "${IMPL_ARGS[@]}" > "$RUN_LOG" 2>&1
IMPL_RC=$?
set -e
cat "$RUN_LOG" >&2
if [ "$IMPL_RC" -ne 0 ]; then
  echo "  ✗ Implementer failed (rc $IMPL_RC) — review skipped." >&2
  exit 1
fi
if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] no PR exists — review stage skipped." >&2
  exit 0
fi
if [ "$IMPL_ONLY" = true ]; then
  echo "  --implement-only: chain ends here. Review when ready: bin/review-run.sh --pick" >&2
  exit 0
fi

# Resolve the raised PR. The implementer's run log is authoritative — it just
# created the PR, while the task file's decision-06 tracking row may hold a
# STALE URL from a previous run's sync (reviewing the wrong PR silently).
# Fall back to the task-file row, then --pick.
SLUG="$TASK_ARG"
if [ -z "$SLUG" ]; then
  SLUG="$(grep -oE 'docs/tasks/[^ ]+\.md' "$RUN_LOG" | head -1 | sed -E 's#docs/tasks/(.*)\.md#\1#' || true)"
fi
PR_ARG="$(grep -m1 -oE 'https://[^[:space:]]+/pull/[0-9]+' "$RUN_LOG" 2>/dev/null || true)"
if [ -z "$PR_ARG" ] && [ -n "$SLUG" ] && [ -f "$WORKSPACE/docs/tasks/$SLUG.md" ]; then
  PR_ARG="$(sed -n 's/^- URL: //p' "$WORKSPACE/docs/tasks/$SLUG.md" | head -1 || true)"
fi
[ -z "$PR_ARG" ] && PR_ARG="--pick"

# ─── UAT / human gate ─────────────────────────────────────────────────────
# Decision 04: headless mode has NO gate — the loop is fully autonomous.
if [ "$HEADLESS" != true ] && [ "$YES" != true ]; then
  echo ""
  echo "══════════════════════════════════════════════════════════════════"
  echo "  HUMAN GATE — PR $PR_ARG is open."
  echo "  Do your UAT on the PR now; the autonomous review runs after."
  echo "  The merge is NOT part of this chain (decisions 05/07):"
  echo "  after review + your UAT, merge yourself: bin/merge-pr.sh <n>"
  echo "══════════════════════════════════════════════════════════════════"
  if ! read -r -p "Proceed with the code review now? [Y/n] " ANS; then
    # EOF (non-interactive stdin): we could NOT get a human decision — defer
    # rather than auto-approve the gate. Use --yes to skip the prompt on
    # purpose.
    echo "  Non-interactive stdin — UAT gate aborted (use --yes to proceed)." >&2
    echo "  Deferred — PR left open. Resume later: bin/review-run.sh --pick" >&2
    exit 0
  fi
  case "${ANS:-y}" in
    [Nn]*)
      echo "  Deferred — PR left open. Resume later: bin/review-run.sh --pick" >&2
      exit 0
      ;;
  esac
fi

# ─── Stage 2: review ──────────────────────────────────────────────────────
run_review() {
  local label="$1"; shift
  local -a targets=("$@")
  echo ""
  echo "── Stage 2: code review ($label) ──"
  local -a REV_ARGS=()
  if [ -n "$REVIEW_OVERRIDE" ]; then REV_ARGS+=("$REVIEW_OVERRIDE"); else REV_ARGS+=("${targets[@]}"); fi
  # Multi-repo PR-set flow: per-PR verdicts land in the run dir (review-run.sh
  # merges one key per PR when REVIEWER_SET_VERDICTS is exported), so the headless
  # loop can revise ONLY the rejected repos (US9). Single-repo runs leave it unset.
  if [ -n "${RUN_DIR:-}" ]; then
    export REVIEWER_SET_VERDICTS="$RUN_DIR/review-verdicts.json"
    : > "$REVIEWER_SET_VERDICTS"
  fi
  set +e
  "$REVIEWER" "${REV_ARGS[@]}" > "$REV_LOG" 2>&1
  REV_RC=$?
  set -e
  cat "$REV_LOG" >&2
  if [ "$REV_RC" -ne 0 ]; then
    echo "  ✗ Reviewer failed (rc $REV_RC) — task left in-progress." >&2
    echo "    Re-run when ready: bin/review-run.sh --pick" >&2
    exit 2
  fi
}

# Verdict read-back (decision 04): the review driver archives the report to
# docs/code-reviews/<date>-<slug>/report.md. Read the verdict the same way the
# driver does — the verdict token appears at line start, either bare
# (APPROVE / REQUEST_CHANGES) or markdown-bold (**REQUEST_CHANGES** …). Real
# reports open with "# Code Review", so we do NOT assume line 1. An empty
# verdict (e.g. a "# Partial review" failure report) means non-APPROVE,
# surfaced, no revise.
read_verdict() {
  local slug="$1"
  local rrd
  # PRD decision (J2): verdict read-back switches to the reviewer's RUN_DIR
  # paths (reports/verdict.txt) — the durable run-dir seam review-run.sh writes.
  # Falls back to the checkout archive (docs/code-reviews/...) so stub-driven
  # headless tests (which only archive there) keep working.
  rrd="$(review_run_dir "$slug")"
  if [ -n "$rrd" ] && [ -f "$rrd/reports/verdict.txt" ]; then
    verdict="$(tr -d '[:space:]' < "$rrd/reports/verdict.txt" 2>/dev/null || true)"
    verdict_file="$rrd/reports/verdict.txt"
    [ -n "$verdict" ] && return 0
  fi
  local report="$WORKSPACE/docs/code-reviews/$(date '+%Y-%m-%d')-$slug/report.md"
  if [ ! -f "$report" ]; then
    verdict=""
    verdict_file=""
    return 1
  fi
  verdict_file="$report"
  verdict="$(grep -m1 -oE '^\*\*(APPROVE|REQUEST_CHANGES)\*\*|^(APPROVE|REQUEST_CHANGES)' "$report" 2>/dev/null \
    | tr -d '*[:space:]' || true)"
  return 0
}

surface_report() {
  echo "  ── Last review report (${verdict_file:-n/a}) ──" >&2
  if [ -n "${verdict_file:-}" ] && [ -f "$verdict_file" ]; then cat "$verdict_file" >&2; fi
}

# resolve_run_ctx <slug>: locate the implementer run dir + manifest (story 7) and
# derive the multi-repo PR set (per-repo PR numbers from the manifest, in repo
# order, distinct). Sets RUN_DIR, FMANIFEST, PR_SET (array). Empty PR_SET when no
# manifest (legacy single-repo / no manifest written).
declare -g PR_SET=()
resolve_run_ctx() {
  local slug="$1" prs
  RUN_DIR=""
  FMANIFEST="$(factory_manifest "$slug")"
  PR_SET=()
  if [ -n "$FMANIFEST" ]; then
    RUN_DIR="$(dirname "$FMANIFEST")"
    prs="$(python3 -c 'import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p))
except Exception:
    raise SystemExit
def num(v):
    try: return int(v) if v not in (None,"") else None
    except Exception: return None
print("\n".join(str(num(r.get("pr"))) for k,r in d.get("repos",{}).items() if num(r.get("pr")) is not None))' "$FMANIFEST" 2>/dev/null || true)"
    while IFS= read -r p; do [ -n "$p" ] && PR_SET+=("$p"); done <<< "$prs"
  fi
}

# read_set_verdicts <manifest-dir> <pr...>: read the per-PR verdicts from the
# reviewer's set-verdicts file into the SET_VERDICT associative array (keyed by
# PR number), matching the `repo#pr` keys review-run.sh writes (shape A/N repos).
declare -gA SET_VERDICT=()
read_set_verdicts() {
  SET_VERDICT=()
  local f="$RUN_DIR/review-verdicts.json"
  [ -f "$f" ] || return 0
  local p v
  for p in "$@"; do
    v="$(python3 -c 'import json,sys
target=sys.argv[1]
try:
    d=json.load(open(sys.argv[2]))
except Exception:
    raise SystemExit
for k,v in d.get("repos",{}).items():
    if k.endswith("#"+target):
        print(v.get("verdict","")); break' "$p" "$f" 2>/dev/null || true)"
    SET_VERDICT["$p"]="$v"
  done
}

# revise_pr <pr>: run the implementer revision against ONE PR (US9: only the
# rejected repo is revised). Fails loud (F3) and logs through the run log.
revise_pr() {
  local pr="$1"
  set +e
  "$IMPLEMENTER" --revise "$pr" > "$RUN_LOG" 2>&1
  local rc=$?
  set -e
  cat "$RUN_LOG" >&2
  if [ "$rc" -ne 0 ]; then
    echo "  ✗ Revision implementer failed for PR $pr (rc $rc)." >&2
    return 1
  fi
  return 0
}

# finalize_headless <exit-code>: raise the bookkeeping PR + assert the loop-end A/B
# invariant, then exit. Fail-loud: any bookkeeping/invariant failure forces exit 1
# (F3; review B-1/B-3/B-5).
finalize_headless() {
  local code="$1"
  local bkrc=0 invrc=0
  finish_bookkeeping || bkrc=$?
  if [ -n "${BK_MANIFEST:-}" ] && [ -f "$BK_MANIFEST" ]; then
    assert_loop_end_invariant "$BK_MANIFEST" || invrc=$?
  fi
  if [ "$code" -ne 0 ] || [ "$bkrc" -ne 0 ] || [ "$invrc" -ne 0 ]; then
    exit 1
  fi
  exit 0
}

headless_loop() {
  local slug="$1"
  resolve_run_ctx "$slug"
  local n=0
  local -a targets
  if [ "${#PR_SET[@]}" -ge 2 ]; then
    # Multi-repo shape: review/revise over the whole PR set (US9, review B-4).
    targets=("${PR_SET[@]}")
  else
    targets=("$PR_ARG")
  fi
  while true; do
    run_review "${targets[*]}" "${targets[@]}"
    if [ "${#PR_SET[@]}" -ge 2 ]; then
      read_set_verdicts "$slug" "${targets[@]}"
      local -a rejected=()
      local p
      for p in "${targets[@]}"; do
        case "${SET_VERDICT[$p]:-}" in
          APPROVE*) : ;;
          REQUEST_CHANGES*) rejected+=("$p") ;;
          *) rejected+=("$p") ;;  # empty/unreadable → non-approve, revise
        esac
      done
      if [ "${#rejected[@]}" -eq 0 ]; then
        echo "  ✓ Review APPROVED across all ${#targets[@]} PR(s) (revision $n)." >&2
        finalize_headless 0
        return 0
      fi
      if [ "$n" -lt "$REVISION_CAP" ]; then
        n=$((n+1))
        echo "  ${#rejected[@]} PR(s) REQUEST_CHANGES (revision $n/$REVISION_CAP) — revising ONLY the rejected repo(s): ${rejected[*]}." >&2
        for p in "${rejected[@]}"; do
          revise_pr "$p" || { finalize_headless 1; return 1; }
        done
        # Re-review only the rejected repos (US9) — passing repos stay passed.
        targets=("${rejected[@]}")
        continue
      fi
      echo "  ✗ REQUEST_CHANGES persists after ${REVISION_CAP} revision(s) — cap exhausted (PRs: ${targets[*]})." >&2
      finalize_headless 1
      return 1
    else
      # Single-PR shape (unchanged decision-04 behavior).
      if ! read_verdict "$slug"; then
        echo "  ✗ Verdict unavailable — no review report archived for $slug." >&2
        finalize_headless 1
        return 1
      fi
      case "$verdict" in
        APPROVE*)
          echo "  ✓ Review APPROVED (revision $n). Merge-ready PR — task in-review." >&2
          finalize_headless 0
          return 0
          ;;
        REQUEST_CHANGES*)
          if [ "$n" -lt "$REVISION_CAP" ]; then
            n=$((n+1))
            echo "  Review returned REQUEST_CHANGES (revision $n/$REVISION_CAP) — running implementer-run.sh --revise." >&2
            revise_pr "$PR_ARG" || { finalize_headless 1; return 1; }
          else
            echo "  ✗ REQUEST_CHANGES persists after ${REVISION_CAP} revision(s) — cap exhausted." >&2
            surface_report >&2
            finalize_headless 1
            return 1
          fi
          ;;
        *)
          # Empty / unrecognised verdict (e.g. partial-failure report). Surface,
          # treat as non-APPROVE, do NOT revise (decision 04 contract).
          echo "  ✗ No valid verdict read back (got '${verdict}') — surfacing report, not revising." >&2
          surface_report
          finalize_headless 1
          return 1
          ;;
      esac
    fi
  done
}

if [ "$HEADLESS" = true ]; then
  SLUG="$TASK_ARG"
  if [ -z "$SLUG" ]; then
    SLUG="$(grep -oE 'docs/tasks/[^ ]+\.md' "$RUN_LOG" | head -1 | sed -E 's#docs/tasks/(.*)\.md#\1#' || true)"
  fi
  if [ -z "$SLUG" ]; then
    echo "  ✗ Could not resolve task slug for verdict read-back (use --task <slug>)." >&2
    exit 1
  fi
  headless_loop "$SLUG"
fi

run_review "$PR_ARG" "$PR_ARG"

# Bookkeeping PR is raised at chain end (success OR failure) for Shape A, then the
# full A/B XOR is re-asserted at loop end (PRD + review B-1). Fail-loud (F3).
finish_bookkeeping || exit 1
if [ -n "${BK_MANIFEST:-}" ] && [ -f "$BK_MANIFEST" ]; then
  assert_loop_end_invariant "$BK_MANIFEST" || exit 1
fi

echo ""
echo "── Chain complete: implement + review done ──"
echo "  Master has local tracking commits (PR/review rows) — they go up when"
echo "  you merge: bin/merge-pr.sh $PR_ARG   (after your UAT; decision 05/07)." >&2
exit 0