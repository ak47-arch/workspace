#!/usr/bin/env bash
# ============================================================================
# merge-pr.sh — OPERATOR-side PR-set merge + Merge-row task tracking.
#
# Authority split (decision 05): the code-review agent NEVER merges. This is the
# explicit human-gated go-ahead action: user UAT → run this → gh merges + a
# Merge row is appended to the task file (decision 06) PER PR, and the task
# transitions to complete only when the WHOLE PR set is merged.
#
# Multi-repo delivery (PRD: multi-repo delivery bookkeeping PRs): a task can
# raise a set of PRs (Shape A: N app code PRs + 1 bookkeeping PR; Shape B: 1
# root PR). This script accepts the whole set, pre-flights that all are open,
# merges each, records a Merge row per PR, and completes the task only when the
# set is fully merged.
#
# Usage:
#   bin/merge-pr.sh <pr> [<pr>...] [--slug <slug>] [--dry-run]
#   <pr>    PR to merge: owner/repo#num, full pull URL, or bare number (default
#           repo). Number starts with # or is a plain number. Repeat for a set.
#   --slug  Task slug. Auto-derived from the first PR's title "[factory] <slug>"
#           if omitted.
#   --dry-run  Show what would happen; no merge, no edit.
#
# Exit codes: 0 success (whole set merged) · 1 merge/record/pre-flight failure ·
# 2 usage.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test seam: MERGE_WORKSPACE + MERGE_DEFAULT_REPO let fixtures run this offline.
WORKSPACE="${MERGE_WORKSPACE:-$SCRIPT_DIR}"

PRS=()
SLUG=""
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) PRS+=("$1"); shift ;;
  esac
done
if [ "${#PRS[@]}" -eq 0 ]; then
  echo "Usage: bin/merge-pr.sh <pr> [<pr>...] [--slug <slug>] [--dry-run]" >&2
  exit 2
fi

# ─── Resolve owner/repo + number for each PR arg ───────────────────────────
resolve_pr() {
  local arg="$1" out="$2"
  local repo num
  case "$arg" in
    http*)
      repo="$(printf '%s' "$arg" | sed -E 's#https://github.com/([^/]+)/([^/]+)/pull/[0-9]+.*#\1/\2#')"
      num="$(printf '%s' "$arg" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
      ;;
    */*#*)
      repo="${arg%#*}"; num="${arg##*#}"
      ;;
    *#*)
      repo="${MERGE_DEFAULT_REPO:-ak47-arch/workspace}"; num="${arg##*#}"
      ;;
    *)
      repo="${MERGE_DEFAULT_REPO:-ak47-arch/workspace}"; num="$arg"
      ;;
  esac
  printf '%s %s\n' "$repo" "$num" > "$out"
}

# ─── Pre-flight: all PRs must be open, nothing already merged/closed ───────
PREFLIGHT=()
i=0
for pr in "${PRS[@]}"; do
  tf="$(mktemp)"; resolve_pr "$pr" "$tf"
  read -r REPO NUM < "$tf"; rm -f "$tf"
  # gh 2.45 `pr view --json merged` is NOT a valid field; state=MERGED covers
  # merged + closed. Parse defensively: real gh `--json state` returns JSON, a
  # minimal mock may return `{}` (unknown → proceed, backward compatible).
  state_raw="$(gh pr view "$NUM" --repo "$REPO" --json state 2>/dev/null || true)"
  state="$(printf '%s' "$state_raw" | python3 -c '
import sys, json
try:
    s = sys.stdin.read().strip()
    d = json.loads(s)
    print(d.get("state") or "")
except Exception:
    print(s)' 2>/dev/null || true)"
  if [ -n "$state" ] && [ "$state" != "OPEN" ]; then
    echo "ERROR: PR $REPO#$NUM is not open (state=$state) — refusing to double-merge a partial/stale set." >&2
    echo "  Set so far: ${PREFLIGHT[*]:-none} + $REPO#$NUM (already merged/closed)" >&2
    exit 1
  fi
  PREFLIGHT+=("$REPO#$NUM")
  i=$((i+1))
done
echo "  Pre-flight OK — all ${#PREFLIGHT[@]} PRs open: ${PREFLIGHT[*]}" >&2

# Derive the task slug from the first PR's title if not supplied.
if [ -z "$SLUG" ]; then
  first="${PREFLIGHT[0]}"
  first_repo="${first%#*}"; first_num="${first#*#}"
  SLUG="$(gh pr view "$first_num" --repo "$first_repo" --json title --jq .title 2>/dev/null \
    | sed -nE 's/^\[factory\] ([^:]+):.*/\1/p' || true)"
fi
if [ -z "$SLUG" ]; then
  echo "ERROR: could not derive task slug from PR title (use --slug)" >&2
  exit 2
fi

# ─── Dependency invariant (decision 09): no undeclared ride-along commits ──
# A PR may bring another open PR's unmerged commits ONLY if it declares
# `**Depends on:** #N`. Declared deps also fix merge order (dependencies merge
# first). When PR heads are resolvable (real gh + git available), a PR whose
# branch is a superset of another open PR's branch (head-ancestry) with no
# declared dependency fails loudly — that shared commit's ownership is
# ambiguous, and automatic merging must never guess.
#
# Backward compatible: a minimal gh mock (`{}`) yields no body/head and simply
# skips the ancestry part; declared-dep ordering still applies on body text.
declare -A DEPON=()     # NUM -> declared prerequisite PR number
declare -A HEAD_REF=()  # NUM -> headRefName
json_get() { python3 -c "import sys,json
s=sys.stdin.read() or '{}'
try:
 d=json.loads(s); print(d.get('$1') or '')
except Exception: print('')" 2>/dev/null; }
for pr in "${PREFLIGHT[@]}"; do
  REPO="${pr%#*}"; NUM="${pr#*#}"
  meta="$(gh pr view "$NUM" --repo "$REPO" --json body,headRefName 2>/dev/null || true)"
  BODY="$(printf '%s' "$meta" | json_get body)"
  HEAD_REF[$NUM]="$(printf '%s' "$meta" | json_get headRefName)"
  dnum="$(printf '%s\n' "$BODY" | sed -nE 's/.*\*\*Depends on:\*\*[[:space:]]*#?([0-9]+).*/\1/p' | head -1)"
  if [ -n "$dnum" ]; then DEPON[$NUM]="$dnum"; fi
done
# Every declared dependency must be inside the merge set (no dangling deps).
for NUM in "${!DEPON[@]}"; do
  want="${DEPON[$NUM]}"; in_set=false
  for e in "${PREFLIGHT[@]}"; do [ "${e#*#}" = "$want" ] && in_set=true; done
  if [ "$in_set" = false ]; then
    echo "ERROR: PR #$NUM declares **Depends on:** #$want which is not in the merge set ${PREFLIGHT[*]:-none}." >&2
    exit 1
  fi
done
# Materialize each resolvable PR head locally; enforce the ride-along rule.
UNVERIFIABLE=0
for pr in "${PREFLIGHT[@]}"; do
  NUM="${pr#*#}"; H="${HEAD_REF[$NUM]:-}"
  if [ -n "$H" ] && git -C "$WORKSPACE" fetch -q origin "$H:refs/prheads/$NUM" 2>/dev/null; then
    : # head materialized
  else
    UNVERIFIABLE=1
  fi
done
for A in "${PREFLIGHT[@]}"; do
  ANUM="${A#*#}"
  [ -n "${HEAD_REF[$ANUM]:-}" ] || continue
  for B in "${PREFLIGHT[@]}"; do
    BNUM="${B#*#}"
    [ "$ANUM" != "$BNUM" ] || continue
    [ -n "${HEAD_REF[$BNUM]:-}" ] || continue
    if git -C "$WORKSPACE" merge-base --is-ancestor "refs/prheads/$ANUM" "refs/prheads/$BNUM" 2>/dev/null; then
      # PR B is a superset of PR A: B carries all of A's commits.
      dep="${DEPON[$BNUM]:-}"
      if [ "$dep" != "$ANUM" ]; then
        echo "ERROR: PR #$BNUM brings commits from open PR #$ANUM without declaring **Depends on:** #$ANUM — refusing ambiguous ride-along (decision 09)." >&2
        echo "  Resolve: add \"**Depends on:** #$ANUM\" to PR #$BNUM's body (base merges first), or rebase PR #$BNUM onto master." >&2
        exit 1
      fi
    fi
  done
done
if [ "$UNVERIFIABLE" -eq 1 ] && [ "${#PREFLIGHT[@]}" -gt 1 ]; then
  echo "  WARN: some PR heads unresolvable — ride-along ancestry check skipped for those; declared deps still enforced." >&2
fi

if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] would pre-flight + merge ${PREFLIGHT[*]} and append Merge rows to docs/tasks/$SLUG.md, completing the task only when the whole set is merged."
  exit 0
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/bin/lib-pr-tracking.sh"
TASK="$WORKSPACE/docs/tasks/$SLUG.md"
ACTOR="$(gh api user --jq .login 2>/dev/null || echo operator)"
TS="$(date '+%Y-%m-%d %H:%M')"
MERGED=0

# ─── Merge each PR + record a Merge row per PR ─────────────────────────────
# Order the set so declared dependencies merge first (decision 09). Single-level
# deps (the realistic case): no-dep PRs first, then PRs whose dep is already in.
ORDERED=(); ORDERED_NUMS=()
for pr in "${PREFLIGHT[@]}"; do
  NUM="${pr#*#}"; [ -n "${DEPON[$NUM]:-}" ] && continue
  ORDERED+=("$pr"); ORDERED_NUMS+=("$NUM")
done
for pr in "${PREFLIGHT[@]}"; do
  NUM="${pr#*#}"; dep="${DEPON[$NUM]:-}"; [ -n "$dep" ] || continue
  if [[ " ${ORDERED_NUMS[*]} " == *" $dep "* ]]; then ORDERED+=("$pr"); ORDERED_NUMS+=("$NUM"); fi
done
for pr in "${PREFLIGHT[@]}"; do
  NUM="${pr#*#}"; [[ " ${ORDERED_NUMS[*]} " == *" $NUM "* ]] || ORDERED+=("$pr")
done
PREFLIGHT=( "${ORDERED[@]}" )

for entry in "${PREFLIGHT[@]}"; do
  REPO="${entry%#*}"; NUM="${entry#*#}"
  gh pr merge "$NUM" --repo "$REPO" --merge
  MERGE_SHA="$(gh pr view "$NUM" --repo "$REPO" --json mergeCommit --jq .mergeCommit.oid)"
  if pr_tracking_ensure "$TASK" && ! pr_tracking_has "$TASK" "\[$REPO#$NUM\]"; then
    pr_tracking_add "$TASK" "- Merge: $MERGE_SHA ($TS, $ACTOR — user go-ahead, decision 05) [$REPO#$NUM]"
  fi
  echo "  Merged $REPO#$NUM ($MERGE_SHA); Merge row recorded on task $SLUG." >&2
  MERGED=$((MERGED+1))
done

# ─── Complete transition only when the WHOLE set is merged ─────────────────
if [ "$MERGED" -eq "${#PREFLIGHT[@]}" ]; then
  local_nums=""; local_joined=""
  for entry in "${PREFLIGHT[@]}"; do local_nums="${local_nums} #${entry#*#}"; done
  local_joined="$(echo "$local_nums" | sed -E 's/^ //; s/ /,/g')"
  ( cd "$WORKSPACE" && git add "docs/tasks/$SLUG.md" 2>/dev/null || true
    git diff --cached --quiet || git commit -q -m "task($SLUG): record PR $local_joined merge (set ${MERGED}/${#PREFLIGHT[@]})" )
  if [ -x "$WORKSPACE/bin/transition-task.sh" ]; then
    "$WORKSPACE/bin/transition-task.sh" "$SLUG" --to complete \
      || echo "  WARN: could not transition task $SLUG → complete (resolve manually)." >&2
  fi
  echo "  Merged the whole set (${MERGED}/${#PREFLIGHT[@]}); task $SLUG → complete." >&2
else
  echo "  Partial merge (${MERGED}/${#PREFLIGHT[@]}) — task NOT completed." >&2
  exit 1
fi
exit 0
