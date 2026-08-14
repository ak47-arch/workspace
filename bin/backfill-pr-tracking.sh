#!/usr/bin/env bash
# ============================================================================
# backfill-pr-tracking.sh — one-shot retrospective PR-tracking rows (decision 06).
#
# Retroactively attaches PR data to task files for phases that predate the
# automation (pre-reviewer-era PRs). Idempotent: skips a row already present.
# Table rows: slug|repo|pr|url|branch|base|head|raised_by|note
#   (empty slug = comment; empty head = '?')
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/bin/lib-pr-tracking.sh"

backfill_table="$(cat <<'TABLE'
extension-inline-agent|ak47-arch/feed_analyser|1|https://github.com/ak47-arch/feed_analyser/pull/1|factory/extension-inline-agent/20260812-033024|public-release|24e60a87a6926724c2ef6037d9daf87eaea6ecf7|implementer run 60c0c537|pre-reviewer era (manual verification 2026-08-12)
TABLE
)"

while IFS='|' read -r slug repo pr url branch base head raised_by note; do
  [ -z "$slug" ] && continue
  task="$SCRIPT_DIR/docs/tasks/$slug.md"
  if ! pr_tracking_ensure "$task"; then
    echo "SKIP  $slug (no task file at $task)"
    continue
  fi
  added=""
  if ! pr_tracking_has "$task" "PR: #$pr "; then
    pr_tracking_add "$task" "- PR: #$pr ($repo)"
    pr_tracking_add "$task" "- URL: $url"
    pr_tracking_add "$task" "- Branch: $branch"
    pr_tracking_add "$task" "- Base: $base · Head: ${head:-?}"
    pr_tracking_add "$task" "- Raised by: $raised_by${note:+ · $note}"
    added=1
  fi
  echo "${added:+ADDED }$slug: PR #$pr ${added:-already tracked}"
done <<EOF
${backfill_table}
EOF