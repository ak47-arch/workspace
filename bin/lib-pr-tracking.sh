#!/usr/bin/env bash
# lib-pr-tracking.sh — decision 06: canonical PR-tracking rows in task files.
#
# Sourced by implementer-run.sh (raise hook), review-run.sh (review hook),
# merge-pr.sh (merge hook), and backfill-pr-tracking.sh (retrospective).
#
# Schema (canonical, append-only):
#   ## PR tracking
#   - PR: #<num> (<owner>/<repo>)
#   - URL: <full PR URL>
#   - Branch: factory/<slug>/<ts>
#   - Base: <branch> · Head: <sha> (raised <ts>)
#   - Raised by: implementer run <uuid>
#   - Review: <session uuid> · verdict <APPROVE|REQUEST_CHANGES> · report <path>
#   - Revised: <head-sha> (<ts>, impl session <uuid>, addressing review <r-session>)
#   - Merge: <merge sha> (<ts>, <actor>)

# pr_tracking_ensure <task>: create the '## PR tracking' section if missing.
# Returns 0 when the task file exists and has the section.
pr_tracking_ensure() {
  local task="$1"
  [ -f "$task" ] || return 1
  if ! grep -q '^## PR tracking' "$task" 2>/dev/null; then
    printf '\n## PR tracking\n\n' >> "$task"
  fi
  return 0
}

# pr_tracking_has <task> <egrep-pattern>: 0 if a row matches (idempotency).
pr_tracking_has() {
  local task="$1"; shift
  grep -Eq "$1" "$task" 2>/dev/null
}

# pr_tracking_revised <task> <head-sha> <when> <impl-uuid> <review-session>:
# append a canonical `Revised:` row to the PR tracking section (revision mode,
# decision 08). Idempotent on the head SHA.
pr_tracking_revised() {
  local task="$1" head="$2" when="$3" impl="$4" review="$5"
  pr_tracking_ensure "$task" || return 1
  if pr_tracking_has "$task" "Revised: $head"; then
    return 0
  fi
  pr_tracking_add "$task" \
    "- Revised: $head ($when, impl session $impl, addressing review $review)"
}
# pr_tracking_add <task> <line>: append <line> to the rows of the section
# (inserted just before the next '## ' header or EOF, so rows accumulate in
# chronological order).
pr_tracking_add() {
  local task="$1"; shift
  pr_tracking_ensure "$task" || return 1
  local line="$*"
  awk -v ins="$line" '
    /^## PR tracking/ { insec=1 }
    insec && /^## / && !/^## PR tracking/ { print ins; insec=0 }
    { print }
    END { if (insec) print ins }
  ' "$task" > "$task.prtrk" && mv "$task.prtrk" "$task"
}
