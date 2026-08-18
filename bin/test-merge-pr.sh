#!/usr/bin/env bash
# test-merge-pr.sh — unit suite for the operator merge script (decision 05/06).
set -u
PASS=0; FAIL=0; FAILED_TESTS=()
pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

FIX="$(mktemp -d)"
mkdir -p "$FIX/docs/tasks"
# Fixture task with a PR-tracking section (as the raise hook would leave it).
cat > "$FIX/docs/tasks/demo.md" <<'TASK'
# Task: demo

**Status**: in-review

## PR tracking

- PR: #7 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/7
- Branch: factory/demo/20260814
- Base: master · Head: aaaa (raised 2026-08-14 10:00)
- Raised by: implementer run 1234
TASK
( cd "$FIX" && git init -q -b master && git config user.email m@e.c && git config user.name M \
  && git add -A && git commit -qm base )

# Mock gh: pr merge + pr view (mergeCommit) + api user.
cat > "$FIX/mock-gh.sh" <<'MOCK'
#!/usr/bin/env bash
LOG="$MERGE_GH_LOG"
{ printf 'gh'; for a in "$@"; do printf ' <%s>' "$a"; done; printf '\n'; } >> "$LOG"
case "$1" in
  pr)
    case "$2" in
      merge) printf 'merged #7\n' ;;
      view)
        if [[ "$*" == *"mergeCommit"* ]]; then
          printf 'f00d1234567890abcdef1234567890abcdef12'
        elif [[ "$*" == *"title"* ]]; then
          # emulate `--jq .title` (real gh returns the bare title string)
          printf '[factory] demo: implement'
        else
          printf '{}'
        fi
        ;;
    esac
    ;;
  api) printf 'operator-user\n' ;;
esac
exit 0
MOCK
chmod +x "$FIX/mock-gh.sh"

echo "── merge-pr.sh: usage + dry-run ──"
bash bin/merge-pr.sh 2>&1 | grep -q "Usage" && pass "no-arg shows usage (exit 2)"
bash bin/merge-pr.sh --dry-run 2>&1 | grep -q "Usage" && pass "--dry-run alone still requires <pr>"

export MERGE_WORKSPACE="$FIX" MERGE_DEFAULT_REPO="ak47-arch/workspace"
export MERGE_GH_BIN="$FIX/mock-gh.sh" MERGE_GH_LOG="$FIX/gh-calls.log"
: > "$MERGE_GH_LOG"

# Real subprocess: mock gh via PATH shim (script calls bare `gh`).
mkdir -p "$FIX/pathshim"
ln -sf "$FIX/mock-gh.sh" "$FIX/pathshim/gh"
PATH="$FIX/pathshim:$PATH" bash bin/merge-pr.sh 7 > "$FIX/merge.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "merge 7 exits 0" || fail "merge 7 rc=$rc: $(tail -2 "$FIX/merge.out" | tr '\n' ' ')"
grep -q "<merge> <7> <--repo> <ak47-arch/workspace> <--merge>" "$MERGE_GH_LOG" \
  && pass "gh pr merge --merge invoked (merge commit)" || fail "merge invocation wrong: $(cat "$MERGE_GH_LOG")"
grep -q "Merge: f00d1234567890abcdef1234567890abcdef12" "$FIX/docs/tasks/demo.md" \
  && pass "Merge row appended (sha + actor)" || fail "Merge row missing"
grep -q "operator-user" "$FIX/docs/tasks/demo.md" && pass "actor recorded from gh api user" || fail "actor missing"
grep -q '^## PR tracking' "$FIX/docs/tasks/demo.md" && pass "PR tracking section preserved" || fail "section lost"
# Task file committed + pushed (mock push fails → warning, but commit must exist).
git -C "$FIX" log --oneline -2 | grep -q "record PR #7 merge" && pass "task commit created" || fail "task commit missing"

# ─── Multi-PR merge (PRD: multi-repo delivery bookkeeping PRs) ─────────────
# A task raises a PR SET (Shape A: app code PRs + bookkeeping PR). merge-pr.sh
# must pre-flight all-open (abort if one is already merged), merge each,
# record a Merge row per PR, and complete the task only when the WHOLE set is
# merged.
echo "── multi-PR merge: pre-flight + per-PR rows + complete-on-whole-set ──"
M="$(mktemp -d)"
mkdir -p "$M/docs/tasks"
cat > "$M/docs/tasks/multi.md" <<'TASK'
# Task: multi

**Status**: in-review

## PR tracking

- PR: #8 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/8
- Raised by: implementer run m1
TASK
( cd "$M" && git init -q -b master && git config user.email m@e.c && git config user.name M \
  && git add -A && git commit -qm base )
# Mock gh that answers PR state/mergeCommit/title and logs merges. `state`
# returns OPEN for #8/#9 but MERGED for #10 (pre-flight abort case).
cat > "$M/mock-gh.sh" <<'MOCK'
#!/usr/bin/env bash
LOG="$MERGE_GH_LOG"
{ printf 'gh'; for a in "$@"; do printf ' <%s>' "$a"; done; printf '\n'; } >> "$LOG"
case "$1" in
  pr)
    case "$2" in
      merge) printf 'merged #%s\n' "$3" ;;
      view)
        if [[ "$*" == *"mergeCommit"* ]]; then printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        elif [[ "$*" == *"title"* ]]; then printf '[factory] multi: implement'
        elif [[ "$*" == *"state"* ]]; then
          case "$3" in 10) printf '{"state":"MERGED"}';; *) printf '{"state":"OPEN"}';; esac
        else printf '{}'; fi
        ;;
    esac
    ;;
  api) printf 'operator-user\n' ;;
esac
exit 0
MOCK
chmod +x "$M/mock-gh.sh"
mkdir -p "$M/pathshim"; ln -sf "$M/mock-gh.sh" "$M/pathshim/gh"
mkdir -p "$M/bin"
printf '#!/usr/bin/env bash\necho transition "$*" >> "$TRANSITION_LOG"\nexit 0\n' > "$M/bin/transition-task.sh"
chmod +x "$M/bin/transition-task.sh"

# Pre-flight: one already-merged PR (#10) → abort with the split, no merges.
export MERGE_WORKSPACE="$M" MERGE_DEFAULT_REPO="ak47-arch/workspace" \
  MERGE_GH_LOG="$M/gh-pre.log" TRANSITION_LOG="$M/transition-pre.log"
: > "$MERGE_GH_LOG"; : > "$TRANSITION_LOG"
PATH="$M/pathshim:$PATH" bash bin/merge-pr.sh 8 10 --slug multi > "$M/pre.out" 2>&1
rc=$?
[ "$rc" -eq 1 ] && pass "multi pre-flight: already-merged PR aborts (exit 1)" || fail "multi pre-flight rc=$rc"
grep -q "not open (state=MERGED)" "$M/pre.out" \
  && pass "multi pre-flight: names the merged PR + state" || fail "multi pre-flight message: $(cat "$M/pre.out" | tr '\n' ' ')"
! grep -q '<merge>' "$MERGE_GH_LOG" && pass "multi pre-flight: NO merge invoked on abort" || fail "multi pre-flight: merge ran despite abort: $(cat "$MERGE_GH_LOG" | tr '\n' ' ')"
if [ -s "$TRANSITION_LOG" ]; then fail "multi pre-flight: transition ran on abort"; else pass "multi pre-flight: no transition on abort"; fi

# Full multi-merge: #8 + #9 both open → merge each, two Merge rows, complete.
export MERGE_GH_LOG="$M/gh-multi.log" TRANSITION_LOG="$M/transition-multi.log"
: > "$MERGE_GH_LOG"; : > "$TRANSITION_LOG"
PATH="$M/pathshim:$PATH" bash bin/merge-pr.sh 8 9 --slug multi > "$M/multi.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "multi merge: whole set exits 0" || fail "multi merge rc=$rc: $(tail -2 "$M/multi.out" | tr '\n' ' ')"
grep -q '<merge> <8>' "$MERGE_GH_LOG" && grep -q '<merge> <9>' "$MERGE_GH_LOG" \
  && pass "multi merge: both PRs merged (gh pr merge #8 + #9)" || fail "multi merge: merge invocations: $(cat "$MERGE_GH_LOG" | tr '\n' ' ')"
merge_rows="$(grep -c '^- Merge: aaaaaaaa' "$M/docs/tasks/multi.md")"
[ "$merge_rows" -eq 2 ] && pass "multi merge: one Merge row per PR (2 rows)" || fail "multi merge Merge rows=$merge_rows: $(sed -n '/## PR tracking/,$p' "$M/docs/tasks/multi.md" | tr '\n' ' ')"
if [ -s "$TRANSITION_LOG" ] && grep -q "multi --to complete" "$TRANSITION_LOG"; then
  pass "multi merge: task transitions to complete when whole set merged"
else
  fail "multi merge: complete transition missing: $(cat "$TRANSITION_LOG" 2>/dev/null | tr '\n' ' ')"
fi
git -C "$M" log --oneline -1 | grep -qE "record PR .*merge" \
  && pass "multi merge: task commit created" || fail "multi merge: task commit missing"

# Partial: a merge failure (mock returns non-zero for #13) → no complete.
cat > "$M/mock-gh-fail.sh" <<'MOCK'
#!/usr/bin/env bash
echo "gh $*" >> "$MERGE_GH_LOG"
case "$1" in pr)
  case "$2" in
    merge) [ "$3" = "13" ] && exit 1; printf 'merged\n' ;;
    view) [[ "$*" == *"state"* ]] && printf '{"state":"OPEN"}' || printf '{}' ;;
  esac;;
esac
exit 0
MOCK
chmod +x "$M/mock-gh-fail.sh"
mkdir -p "$M/shimfail"; ln -sf "$M/mock-gh-fail.sh" "$M/shimfail/gh"
export MERGE_GH_LOG="$M/gh-partial.log" TRANSITION_LOG="$M/transition-partial.log"
: > "$MERGE_GH_LOG"; : > "$TRANSITION_LOG"
PATH="$M/shimfail:$PATH" bash bin/merge-pr.sh 12 13 --slug multi > "$M/partial.out" 2>&1
rc=$?
[ "$rc" -eq 1 ] && pass "multi partial: merge failure → exit 1, no complete" || fail "multi partial rc=$rc"
if [ -s "$TRANSITION_LOG" ]; then fail "multi partial: complete transition ran on partial merge"; else pass "multi partial: no complete transition on partial"; fi

unset MERGE_WORKSPACE MERGE_DEFAULT_REPO MERGE_GH_LOG TRANSITION_LOG
rm -rf "$M"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "merge-pr: $PASS passed, $FAIL failed"
rm -rf "$FIX"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
