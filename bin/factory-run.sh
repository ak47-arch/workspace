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

# ─── Stage 1: implement ───────────────────────────────────────────────────
echo ""
echo "── Stage 1: implementer ──"
IMPL_ARGS=()
if [ -n "$TASK_ARG" ]; then IMPL_ARGS+=(--task "$TASK_ARG"); else IMPL_ARGS+=(--pick); fi
[ "$DRY_RUN" = true ] && IMPL_ARGS+=(--dry-run)
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

# Resolve the raised PR from the task file's decision-06 tracking row.
SLUG="$TASK_ARG"
if [ -z "$SLUG" ]; then
  SLUG="$(grep -oE 'docs/tasks/[^ ]+\.md' "$RUN_LOG" | head -1 | sed -E 's#docs/tasks/(.*)\.md#\1#' || true)"
fi
PR_ARG=""
if [ -n "$SLUG" ] && [ -f "$WORKSPACE/docs/tasks/$SLUG.md" ]; then
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
# driver does (grep -m1 '^APPROVE|^REQUEST_CHANGES'). Real reports open with
# "# Code Review", so we do NOT assume line 1. An empty verdict (e.g. a
# "# Partial review" failure report) means non-APPROVE, surfaced, no revise.
read_verdict() {
  local slug="$1"
  local report="$WORKSPACE/docs/code-reviews/$(date '+%Y-%m-%d')-$slug/report.md"
  if [ ! -f "$report" ]; then
    verdict=""
    verdict_file=""
    return 1
  fi
  verdict_file="$report"
  verdict="$(grep -m1 '^APPROVE\|^REQUEST_CHANGES' "$report" 2>/dev/null | tr -d '[:space:]' || true)"
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
            exit 1
          fi
        else
          echo "  ✗ REQUEST_CHANGES persists after ${REVISION_CAP} revision(s) — cap exhausted." >&2
          surface_report
          exit 1
        fi
        ;;
      *)
        # Empty / unrecognised verdict (e.g. partial-failure report). Surface,
        # treat as non-APPROVE, do NOT revise (decision 04 contract).
        echo "  ✗ No valid verdict read back (got '${verdict}') — surfacing report, not revising." >&2
        surface_report
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

echo ""
echo "── Chain complete: implement + review done ──"
echo "  Master has local tracking commits (PR/review rows) — they go up when"
echo "  you merge: bin/merge-pr.sh $PR_ARG   (after your UAT; decision 05/07)." >&2
exit 0