#!/usr/bin/env bash
# test-factory-run.sh — unit suite for the implement→review orchestrator.
#
# Uses stub drivers (FA_RUN_IMPLEMENTER / FA_RUN_REVIEWER) + a fixture task
# file, so the chain's logic is tested without any real agent/gh/git.
set -u
PASS=0; FAIL=0; FAILED_TESTS=()
pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

FIX="$(mktemp -d)"
mkdir -p "$FIX/docs/tasks"
cat > "$FIX/docs/tasks/demo.md" <<'TASK'
# Task: demo

**Status**: in-progress

## PR tracking

- PR: #7 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/7
- Branch: factory/demo/20260814
- Base: master · Head: aaaa (raised 2026-08-14 11:00)
- Raised by: implementer run 1234
TASK

# Stub drivers: log every invocation to $FA_LOG, honor $FA_IMPL_EXIT/$FA_REV_EXIT.
cat > "$FIX/stub-implementer.sh" <<'STUB'
#!/usr/bin/env bash
printf 'implementer %s\n' "$*" >> "$FA_LOG"
printf '  Task PR tracking: #7 recorded on docs/tasks/demo.md\n'
exit "${FA_IMPL_EXIT:-0}"
STUB
cat > "$FIX/stub-reviewer.sh" <<'STUB'
#!/usr/bin/env bash
printf 'reviewer %s\n' "$*" >> "$FA_LOG"
exit "${FA_REV_EXIT:-0}"
STUB
chmod +x "$FIX/stub-implementer.sh" "$FIX/stub-reviewer.sh"

export FACTORY_WORKSPACE="$FIX"
export FA_RUN_IMPLEMENTER="$FIX/stub-implementer.sh"
export FA_RUN_REVIEWER="$FIX/stub-reviewer.sh"
export FA_LOG="$FIX/calls.log"
DRIVER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/factory-run.sh"

echo "── factory-run.sh: usage + defaults ──"
: > "$FA_LOG"
bash "$DRIVER" --bogus 2>/dev/null; rc=$?
[ "$rc" -eq 3 ] && pass "unknown flag → usage exit 3" || fail "unknown-flag rc=$rc"
bash "$DRIVER" --help | grep -q "Usage:" && pass "--help prints usage" || fail "--help output missing"
# No args → implementer defaults to --pick (mirrors implementer-run.sh).
: > "$FA_LOG"
bash "$DRIVER" < /dev/null > "$FIX/out0.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "no-args runs the chain (defaults), deferred at gate" || fail "no-args rc=$rc"
grep -q "implementer --pick" "$FA_LOG" && pass "no-args → implementer --pick" || fail "no-args didn't default to --pick: $(cat "$FA_LOG" | tr '\n' ' ')"

echo "── happy path: implement → UAT(--yes) → review ──"
: > "$FA_LOG"
bash "$DRIVER" --task demo --yes > "$FIX/out1.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "chain exits 0" || fail "chain rc=$rc: $(tail -2 "$FIX/out1.log" | tr '\n' ' ')"
first="$(head -1 "$FA_LOG")"; second="$(sed -n 2p "$FA_LOG")"
[[ "$first" == implementer* ]] && pass "implementer runs first" || fail "order: first=$first"
[[ "$second" == *"reviewer https://github.com/ak47-arch/workspace/pull/7"* ]] \
  && pass "reviewer invoked with the raised PR URL (from task tracking row)" \
  || fail "reviewer arg: $second"
grep -q "reviewer --pick" "$FA_LOG" && fail "--pick fallback used despite URL row" || pass "no --pick fallback needed"

echo "── UAT gate: declined (no --yes) defers, reviewer not called ──"
: > "$FA_LOG"
printf 'n\n' | bash "$DRIVER" --task demo > "$FIX/out2.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "declined at gate → exit 0 (deferred)" || fail "declined rc=$rc"
grep -q "reviewer" "$FA_LOG" && fail "reviewer ran despite decline" || pass "reviewer NOT run on decline"

echo "── UAT gate: EOF without --yes defers safely ──"
: > "$FA_LOG"
bash "$DRIVER" --task demo < /dev/null > "$FIX/out3.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "Deferred" "$FIX/out3.log" && pass "EOF at gate → deferred, exit 0" || fail "EOF gate rc=$rc"
grep -q "reviewer" "$FA_LOG" && fail "reviewer ran on EOF" || pass "reviewer NOT run on EOF"

echo "── failure propagation ──"
: > "$FA_LOG"
FA_IMPL_EXIT=1 bash "$DRIVER" --task demo --yes > "$FIX/out4.log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "implementer failure → exit 1" || fail "impl-fail rc=$rc"
grep -q "reviewer" "$FA_LOG" && fail "reviewer ran after implementer failure" || pass "reviewer skipped on implementer failure"

: > "$FA_LOG"
FA_REV_EXIT=1 bash "$DRIVER" --task demo --yes > "$FIX/out5.log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && pass "reviewer failure → exit 2" || fail "rev-fail rc=$rc"

echo "── --implement-only and --dry-run ──"
: > "$FA_LOG"
bash "$DRIVER" --task demo --implement-only > "$FIX/out6.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "implement-only exits 0" || fail "impl-only rc=$rc"
grep -q "reviewer" "$FA_LOG" && fail "reviewer ran under --implement-only" || pass "reviewer NOT run under --implement-only"

: > "$FA_LOG"
bash "$DRIVER" --task demo --yes --dry-run > "$FIX/out7.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "dry-run exits 0" || fail "dry-run rc=$rc"
grep -q "implementer --task demo --dry-run" "$FA_LOG" && pass "--dry-run forwarded to implementer" || fail "dry-run not forwarded: $(cat "$FA_LOG" | tr '\n' ' ')"
grep -q "reviewer" "$FA_LOG" && fail "reviewer ran in dry-run" || pass "reviewer NOT run in dry-run (no PR exists)"

echo "── headless: --headless flag + dry-run (decision 04) ──"
# A verdict-writing stub reviewer: consumes scripted verdicts (one per line in
# $FA_VERDICTS) and writes the archived review report the headless loop reads.
cat > "$FIX/stub-reviewer-verdict.sh" <<'STUB'
#!/usr/bin/env bash
printf 'reviewer %s\n' "$*" >> "$FA_LOG"
verdict="$(head -1 "$FA_VERDICTS" 2>/dev/null || true)"
[ -n "$verdict" ] && sed -i '1d' "$FA_VERDICTS" || verdict="APPROVE"
slug="${FA_SLUG:-demo}"
report="${FACTORY_WORKSPACE:-.}/docs/code-reviews/$(date '+%Y-%m-%d')-$slug/report.md"
mkdir -p "$(dirname "$report")"
case "$verdict" in
  PARTIAL)
    { echo "# Partial review"; echo ""; echo "Run failed: exploded"; } > "$report"
    ;;
  *)
    { echo "# Code Review"; echo ""; echo "## Verdict"; echo "$verdict"; } > "$report"
    ;;
esac
exit "${FA_REV_EXIT:-0}"
STUB
# A silent reviewer that archives nothing (missing-report path).
cat > "$FIX/stub-reviewer-silent.sh" <<'STUB'
#!/usr/bin/env bash
printf 'reviewer %s\n' "$*" >> "$FA_LOG"
exit 0
STUB
chmod +x "$FIX/stub-reviewer-verdict.sh" "$FIX/stub-reviewer-silent.sh"

: > "$FA_LOG"
bash "$DRIVER" --task demo --headless --dry-run > "$FIX/outH0.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "headless dry-run exits 0" || fail "headless-dry-run rc=$rc"
grep -q "reviewer" "$FA_LOG" && fail "reviewer ran in headless dry-run" || pass "headless dry-run skips review (no PR)"

# Switch to the verdict-writing reviewer for the loop tests.
export FA_RUN_REVIEWER="$FIX/stub-reviewer-verdict.sh"

echo "── headless: APPROVE-first stops the loop ──"
: > "$FA_LOG"
export FA_VERDICTS="$FIX/verdicts-approve"
printf 'APPROVE\n' > "$FA_VERDICTS"
bash "$DRIVER" --task demo --headless > "$FIX/outH1.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "headless APPROVE exits 0" || fail "headless-approve rc=$rc"
count="$(grep -c 'reviewer ' "$FA_LOG")"
[ "$count" -eq 1 ] && pass "reviewer ran once on APPROVE (count=$count)" || fail "reviewer count=$count on APPROVE"
grep -q "implementer --revise" "$FA_LOG" && fail "revise ran on APPROVE" || pass "no revise on APPROVE"

: > "$FA_LOG"
bash "$DRIVER" --task demo --headless < /dev/null > "$FIX/outH2.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "APPROVED" "$FIX/outH2.log" && pass "headless skips UAT gate (no stdin interaction)" || fail "headless gate-skip rc=$rc"

echo "── headless: REQUEST_CHANGES → revise → APPROVE ──"
: > "$FA_LOG"
printf 'REQUEST_CHANGES\nAPPROVE\n' > "$FA_VERDICTS"
bash "$DRIVER" --task demo --headless > "$FIX/outH3.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "headless revise-then-approve exits 0" || fail "headless-revise-approve rc=$rc"
rev_count="$(grep -c 'implementer --revise' "$FA_LOG")"
[ "$rev_count" -eq 1 ] && pass "1 revise ran (rev_count=$rev_count)" || fail "revise count=$rev_count"
rev_count="$(grep -c 'reviewer ' "$FA_LOG")"
[ "$rev_count" -eq 2 ] && pass "2 reviews ran (rev_count=$rev_count)" || fail "review count=$rev_count"

echo "── headless: cap exhaustion (REVISION_CAP=2) fails + surfaces report ──"
: > "$FA_LOG"
printf 'REQUEST_CHANGES\nREQUEST_CHANGES\nREQUEST_CHANGES\n' > "$FA_VERDICTS"
REVISION_CAP=2 bash "$DRIVER" --task demo --headless > "$FIX/outH4.log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "headless cap exhaustion exits 1" || fail "headless-cap rc=$rc"
rev_count="$(grep -c 'implementer --revise' "$FA_LOG")"
[ "$rev_count" -eq 2 ] && pass "exactly REVISION_CAP revises ran (rev_count=$rev_count)" || fail "revise count=$rev_count"
grep -q "cap exhausted" "$FIX/outH4.log" && pass "cap exhaustion reported" || fail "cap exhaustion not reported"

: > "$FA_LOG"
printf 'REQUEST_CHANGES\nREQUEST_CHANGES\nREQUEST_CHANGES\n' > "$FA_VERDICTS"
REVISION_CAP=0 bash "$DRIVER" --task demo --headless > "$FIX/outH5.log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'implementer --revise' "$FA_LOG" && fail "revise ran with REVISION_CAP=0" || pass "REVISION_CAP=0 → no revise, exit 1 (rc=$rc)"

echo "── headless: empty verdict / partial report → surface, no revise ──"
: > "$FA_LOG"
printf 'PARTIAL\n' > "$FA_VERDICTS"
bash "$DRIVER" --task demo --headless > "$FIX/outH6.log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "empty verdict → exit 1" || fail "empty-verdict rc=$rc"
grep -q "implementer --revise" "$FA_LOG" && fail "revise ran on empty verdict" || pass "no revise on empty verdict"
grep -q "Partial review" "$FIX/outH6.log" && pass "partial report surfaced" || fail "partial report not surfaced"

echo "── headless: missing archived report → surface, exit 1 ──"
export FA_RUN_REVIEWER="$FIX/stub-reviewer-silent.sh"
: > "$FA_LOG"
rm -rf "$FIX/docs/code-reviews"
bash "$DRIVER" --task demo --headless > "$FIX/outH7.log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "missing report → exit 1" || fail "missing-report rc=$rc"
grep -q "Verdict unavailable" "$FIX/outH7.log" && pass "missing report surfaced" || fail "missing-report not surfaced"
export FA_RUN_REVIEWER="$FIX/stub-reviewer-verdict.sh"

echo "── authority split: chain never touches merge ──"
grep -q "merge-pr" "$DRIVER" && { grep -q "bin/merge-pr.sh" "$DRIVER" && pass "merge-pr referenced only as operator guidance text" || fail "unexpected merge-pr reference"; } || true
: > "$FA_LOG"
bash "$DRIVER" --task demo --yes > /dev/null 2>&1
if grep -q "merge" "$FA_LOG"; then fail "a stub received a merge call"; else pass "no merge call reaches any driver"; fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "factory-run: $PASS passed, $FAIL failed"
rm -rf "$FIX"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."