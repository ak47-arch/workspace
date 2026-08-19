#!/usr/bin/env bash
# test-session-filter.sh — unit suite for bin/session-filter.sh.
#
# Locks the evidence-stream fix (decision 05 / session-filter): the message-
# level pi narrative survives the filter; the per-keystroke `message_update`
# delta-replay is dropped. Dropping is anchored to the record's TOP-LEVEL type,
# so no kept record's content/args can be mismatched.
set -u
PASS=0; FAIL=0; FAILED_TESTS=()
pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$(mktemp -d)"
IN="$F/in.jsonl"; OUT="$F/out.jsonl"

# A realistic stream slice: agent/turn framing, a user message, THREE
# message_update delta records (thinking/toolcall/text), the tool_execution
# start, a tool_execution_update carrying partial output, the tool_execution
# end, one message_end carrying usage, and turn_end.
cat > "$IN" <<'STREAM'
{"type":"agent_start"}
{"type":"turn_start"}
{"type":"message_start","message":{"role":"user","content":[{"type":"text","text":"go"}]}}
{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","delta":"Let"},"message":{"role":"assistant"}}
{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","delta":"cd /x"},"message":{"role":"assistant","content":[{"type":"toolCall"}]}}
{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":" ok"},"message":{"role":"assistant"}}
{"type":"message_end","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash","arguments":{"command":"echo hi"}}]},"usage":{"totalTokens":10}}
{"type":"tool_execution_start","toolName":"bash","args":{"command":"echo hi"}}
{"type":"tool_execution_update","toolName":"bash","args":{"command":"echo hi"},"partialResult":{"content":[{"type":"text","text":"hi"}]}}
{"type":"tool_execution_end"}
{"type":"turn_end"}
STREAM

# Run the filter.
"$ROOT/bin/session-filter.sh" < "$IN" > "$OUT" || fail "session-filter exited non-zero"

# 1) Must drop the delta-replay records entirely.
MU=$(grep -c '"type":"message_update"' "$OUT" || true)
[ "$MU" = "0" ] && pass "zero message_update records remain" || fail "zero message_update remain (got $MU)"

# 2) Must keep exactly the message-level narrative, in order.
KEPT=$(grep -o '^{"type":"[A-Za-z_]*' "$OUT" | sed 's/^{"type":"//' | tr "\n" " ")
EXP="agent_start turn_start message_start message_end tool_execution_start tool_execution_update tool_execution_end turn_end "
[ "$KEPT" = "$EXP" ] && pass "keeps exactly the message-level narrative, in order" || fail "keeps exactly the message-level narrative in order (got: $KEPT; want: $EXP)"

# 3) Real partial output survives (not a delta).
grep -q '"type":"tool_execution_update"' "$OUT" && pass "keeps tool_execution_update (real output)" || fail "keeps tool_execution_update"

# 4) The filter itself must parse cleanly.
bash -n "$ROOT/bin/session-filter.sh" && pass "session-filter.sh parses (bash -n)" || fail "session-filter.sh does not parse"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "session-filter: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"; for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
  exit 1
fi
echo "All tests passed."
exit 0