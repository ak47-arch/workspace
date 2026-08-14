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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "merge-pr: $PASS passed, $FAIL failed"
rm -rf "$FIX"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
