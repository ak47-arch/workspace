#!/usr/bin/env bash
# test-merge-pr-deps.sh — unit suite for the PR dependency invariant in
# merge-pr.sh (decision 07-pr-dependency-invariant).
#
# Scenario under test is the real incident that motivated it: PR B is a branch
# STACKED on PR A (its branch contains all of A's commits). Without a declared
# `**Depends on:** #A`, merging B would silently carry A's unmerged work — that
# must be rejected. With the declaration, B is allowed and A is merged FIRST.
set -u
PASS=0; FAIL=0; FAILED_TESTS=()
pass(){ PASS=$((PASS+1)); echo "  ✓ $1"; }
fail(){ FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$(mktemp -d)"

# ── bare origin + clone with three branch-topology states ──────────────────
git init -q --bare "$D/origin.git"
git clone -q "$D/origin.git" "$D/W"
( cd "$D/W" && git config user.email t@e.c && git config user.name T \
  && echo base > base.txt && git add -A && git commit -qm base && git push -q origin master )
# PR #20 (head=factory/base/20): a normal single commit on master.
( cd "$D/W" && git checkout -q -b factory/base/20 && echo A > a.txt && git add -A \
  && git commit -qm "feat A" && git push -q origin factory/base/20 )
# PR #21 (head=factory/stack/21): STACKED on #20's branch (carries feat A).
( cd "$D/W" && git checkout -q factory/base/20 && git checkout -q -b factory/stack/21 \
  && echo B > b.txt && git add -A && git commit -qm "feat B" && git push -q origin factory/stack/21 )
git -C "$D/W" checkout -q master

mkdir -p "$D/W/docs/tasks"
cat > "$D/W/docs/tasks/demo.md" <<'TASK'
# Task: demo

**Status**: in-review

## PR tracking

- PR: #20 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/20
- Raised by: implementer run d1
TASK
( cd "$D/W" && git add -A && git commit -qm "task tracking" )

export MERGE_WORKSPACE="$D/W" MERGE_DEFAULT_REPO="ak47-arch/workspace"
export MERGE_GH_LOG="$D/gh-calls.log"

# Mock gh: returns real JSON for state / body+headRefName keyed by PR number;
# #21's body is read from body21.txt so each test controls the declaration.
cat > "$D/mock-gh.sh" <<MOCK
#!/usr/bin/env bash
LOG="${MERGE_GH_LOG}"; { printf 'gh'; for a in "\$@"; do printf ' <%s>' "\$a"; done; printf '\n'; } >> "\$LOG"
num="\$3"
case "\$*" in
  *headRefName*)
    if [ "\$num" = "20" ]; then printf '{"body":"","headRefName":"factory/base/20"}'
    else printf '{"body":"%s","headRefName":"factory/stack/21"}' "\$(cat "$D/body21.txt")"; fi ;;
  *state*)    printf '{"state":"OPEN"}' ;;
  *mergeCommit*) printf 'c0ffee0000000000000000000000000000000000' ;;
  *title*)    printf '[factory] demo: implement' ;;
  *)          printf '{}' ;;
esac
exit 0
MOCK
chmod +x "$D/mock-gh.sh"
mkdir -p "$D/shim"; ln -sf "$D/mock-gh.sh" "$D/shim/gh"

run_merge() {  # (body21 text) -> prints rc; merges into $D/out so gh-mgcalls separate
  : > "$D/gh-calls.log"
  PATH="$D/shim:$PATH" bash "$ROOT/bin/merge-pr.sh" 20 21 > "$D/out" 2>&1
}

echo "── dependency invariant: undeclared ride-along is rejected ──"
: > "$D/body21.txt"                       # no **Depends on:** declaration
run_merge
rc=$?
if [ "$rc" -eq 1 ] && grep -q "ride-along" "$D/out"; then
  pass "stacked PR without **Depends on:** rejected (exit 1, names ride-along)"
else
  fail "undeclared ride-along not rejected (rc=$rc): $(tail -2 "$D/out" | tr '\n' ' ')"
fi
grep -q "<merge>" "$D/gh-calls.log" && fail "no merge issued on rejected set" || pass "no merge issued on rejected set"

echo "── dependency invariant: declared dependency allowed + ordered ──"
printf '**Depends on:** #20\n' > "$D/body21.txt"
run_merge
rc=$?
if [ "$rc" -eq 0 ]; then pass "stacked PR with declared dep merges cleanly (exit 0)"; else fail "declared dep merge rc=$rc: $(tail -2 "$D/out" | tr '\n' ' ')"; fi
order=$(grep -o '<merge> <[0-9]*>' "$D/gh-calls.log" | grep -o '[0-9]*' | tr '\n' ' ')
[ "$order" = "20 21 " ] && pass "dependency PR #20 merges BEFORE dependent #21 (got: $order)" || fail "merge order wrong ($order) — want '20 21'"

echo "── dependency invariant: dangling dependency rejected ──"
printf '**Depends on:** #99\n' > "$D/body21.txt"     # #99 not in the set
run_merge; rc=$?
if [ "$rc" -eq 1 ] && grep -q "not in the merge set" "$D/out"; then
  pass "declared dep outside the set rejected with clear error"
else
  fail "dangling dependency not rejected (rc=$rc): $(tail -2 "$D/out" | tr '\n' ' ')"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "merge-pr-deps: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"; for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
  exit 1
fi
echo "All tests passed."
exit 0