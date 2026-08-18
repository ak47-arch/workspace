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
  trap 'true' ERR
  local rc=0
  git clone --quiet --local "$WORKSPACE" "$bk_dir/root" 2>/dev/null \
    || git clone --quiet "$WORKSPACE" "$bk_dir/root" || rc=1
  git -C "$bk_dir/root" checkout -q -b "$branch" origin/master 2>/dev/null \
    || git -C "$bk_dir/root" checkout -q -b "$branch" master 2>/dev/null || rc=1
  git -C "$bk_dir/root" config user.name "${IMPL_GIT_NAME:-factory}"
  git -C "$bk_dir/root" config user.email "${IMPL_GIT_EMAIL:-factory@ak47.local}"
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
      --body-file "$body" --label "factory:bookkeeping" 2>/dev/null || true)"
  echo "  Bookkeeping PR raised: $url" >&2
  BK_PR="$url"
  return 0
}

# print_manifest: surface the run manifest at loop end (story 7).
print_manifest() {
  [ -f "$BK_MANIFEST" ] || { echo "  [manifest] none written" >&2; return 0; }
  echo "  ── Run manifest ($BK_MANIFEST) ──" >&2
  cat "$BK_MANIFEST" >&2
}

# finish_bookkeeping: raise the Shape-A bookkeeping PR + print the manifest at
# loop end (success or failure). Active only when a manifest seam is provided
# (BK_MANIFEST) — otherwise a no-op so the legacy single-repo/deferred flows
# are untouched.
finish_bookkeeping() {
  [ -n "${BK_MANIFEST:-}" ] || return 0
  local slug="${TASK_ARG:-$SLUG}"
  [ -n "$slug" ] || return 0
  raise_bookkeeping_pr "$slug" || true
  print_manifest
}

# pickup_gate (story 8): skip this task if an open `[factory] <slug>` PR already
# exists in a declared repo (no re-implementation while in flight). No-op unless
# a gh binary + a repos seam are provided (tests / live GitHub).
# Declared repos come from the PRD **Repos:** header, defaulting to the root.
pickup_gate() {
  local slug="${TASK_ARG:-}"
  [ -n "$slug" ] || return 0
  command -v "$FACTORY_GH_BIN" >/dev/null 2>&1 || return 0
  [ -n "${FACTORY_REPOS:-}" ] || return 0
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
  echo ""
  echo "── Stage 2: code review ($PR_ARG) ──"
  REV_ARGS=()
  if [ -n "$REVIEW_OVERRIDE" ]; then REV_ARGS+=("$REVIEW_OVERRIDE"); else REV_ARGS+=("$PR_ARG"); fi
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

headless_loop() {
  local slug="$1"
  local n=0
  while true; do
    run_review
    if ! read_verdict "$slug"; then
      echo "  ✗ Verdict unavailable — no review report archived for $slug." >&2
      exit 1
    fi
    case "$verdict" in
      APPROVE*)
        echo "  ✓ Review APPROVED (revision $n). Merge-ready PR — task in-review." >&2
        finish_bookkeeping
        exit 0
        ;;
      REQUEST_CHANGES*)
        if [ "$n" -lt "$REVISION_CAP" ]; then
          n=$((n+1))
          echo "  Review returned REQUEST_CHANGES (revision $n/$REVISION_CAP) — running implementer-run.sh --revise." >&2
          set +e
          "$IMPLEMENTER" --revise "$PR_ARG" > "$RUN_LOG" 2>&1
          IMPL_RC=$?
          set -e
          cat "$RUN_LOG" >&2
          if [ "$IMPL_RC" -ne 0 ]; then
            echo "  ✗ Revision implementer failed (rc $IMPL_RC)." >&2
            finish_bookkeeping
            exit 1
          fi
        else
          echo "  ✗ REQUEST_CHANGES persists after ${REVISION_CAP} revision(s) — cap exhausted." >&2
          surface_report >&2
          finish_bookkeeping
          exit 1
        fi
        ;;
      *)
        # Empty / unrecognised verdict (e.g. partial-failure report). Surface,
        # treat as non-APPROVE, do NOT revise (decision 04 contract).
        echo "  ✗ No valid verdict read back (got '${verdict}') — surfacing report, not revising." >&2
        surface_report
        finish_bookkeeping
        exit 1
        ;;
    esac
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

run_review

# Bookkeeping PR is raised at chain end (success OR failure) for Shape A.
finish_bookkeeping

echo ""
echo "── Chain complete: implement + review done ──"
echo "  Master has local tracking commits (PR/review rows) — they go up when"
echo "  you merge: bin/merge-pr.sh $PR_ARG   (after your UAT; decision 05/07)." >&2
exit 0