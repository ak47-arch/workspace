#!/usr/bin/env bash
# ============================================================================
# merge-pr.sh — OPERATOR-side PR merge + Merge-row task tracking.
#
# Authority split (decision 05): the code-review agent NEVER merges. This is the
# explicit human-gated go-ahead action: user UAT → run this → gh merges + the
# Merge row is appended to the task file (decision 06).
#
# Usage:
#   bin/merge-pr.sh <pr> [--slug <slug>] [--dry-run]
#   <pr>    PR to merge: owner/repo#num, full pull URL, or bare number (default
#           repo). Number starts with # or is a plain number.
#   --slug  Task slug. Auto-derived from the PR title "[factory] <slug>: ..."
#           if omitted.
#   --dry-run  Show what would happen; no merge, no edit.
#
# Exit codes: 0 success · 1 merge/record failure · 2 usage.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test seam: MERGE_WORKSPACE + MERGE_DEFAULT_REPO let fixtures run this offline.
WORKSPACE="${MERGE_WORKSPACE:-$SCRIPT_DIR}"

PR_ARG=""; SLUG=""; DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) PR_ARG="$1"; shift ;;
  esac
done
if [ -z "$PR_ARG" ]; then
  echo "Usage: bin/merge-pr.sh <pr> [--slug <slug>] [--dry-run]" >&2
  exit 2
fi

# Resolve owner/repo + number from the argument.
case "$PR_ARG" in
  http*)
    REPO="$(printf '%s' "$PR_ARG" | sed -E 's#https://github.com/([^/]+)/([^/]+)/pull/[0-9]+.*#\1/\2#')"
    NUM="$(printf '%s' "$PR_ARG" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
    ;;
  */*#*)
    REPO="${PR_ARG%#*}"; NUM="${PR_ARG##*#}"
    ;;
  *#*)
    REPO="${MERGE_DEFAULT_REPO:-ak47-arch/workspace}"; NUM="${PR_ARG##*#}"
    ;;
  *)
    REPO="${MERGE_DEFAULT_REPO:-ak47-arch/workspace}"; NUM="$PR_ARG"
    ;;
esac

# Derive the task slug from the PR title if not supplied.
if [ -z "$SLUG" ]; then
  SLUG="$(gh pr view "$NUM" --repo "$REPO" --json title --jq .title 2>/dev/null \
    | sed -nE 's/^\[factory\] ([^:]+):.*/\1/p' || true)"
fi
if [ -z "$SLUG" ]; then
  echo "ERROR: could not derive task slug from PR title (use --slug)" >&2
  exit 2
fi

if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] would merge $REPO#$NUM and append Merge row to docs/tasks/$SLUG.md"
  exit 0
fi

gh pr merge "$NUM" --repo "$REPO" --merge
MERGE_SHA="$(gh pr view "$NUM" --repo "$REPO" --json mergeCommit --jq .mergeCommit.oid)"
ACTOR="$(gh api user --jq .login 2>/dev/null || echo operator)"
TS="$(date '+%Y-%m-%d %H:%M')"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/bin/lib-pr-tracking.sh"
TASK="$WORKSPACE/docs/tasks/$SLUG.md"
if pr_tracking_ensure "$TASK" && ! pr_tracking_has "$TASK" "Merge: $MERGE_SHA"; then
  pr_tracking_add "$TASK" "- Merge: $MERGE_SHA ($TS, $ACTOR — user go-ahead, decision 05)"
  ( cd "$WORKSPACE" && git add "docs/tasks/$SLUG.md" 2>/dev/null || true
    git diff --cached --quiet || git commit -q -m "task($SLUG): record PR #$NUM merge $MERGE_SHA"
    git push origin master 2>/dev/null || echo "  WARN: could not push master (operator push pending)" >&2 )
fi
echo "  Merged $REPO#$NUM ($MERGE_SHA); Merge row recorded on task $SLUG." >&2
exit 0