#!/usr/bin/env bash
# session-filter.sh — strip per-keystroke `message_update` delta-replay from a
# pi event stream (JSONL on stdin → JSONL on stdout).
#
# Why (decision 05): pi emits a `message_update → toolcall_delta` record for
# every keystroke of the agent composing a tool call, and each such record
# re-emits the ENTIRE accumulated partial arguments object — twice per event
# (`assistantMessageEvent.partial` and `message`). Capturing that raw makes a
# session.jsonl/container log grow O(n²) in minutes (this run: 334MB in 34min;
# the remote run hit 2GB and blew GitHub's 100MB evidence cap).
#
# The `message_update` records carry NOTHING durable: the complete narrative is
# in the records we KEEP — `message_start` / `message` / `message_end` (final
# content + usage), `tool_execution_start/end` (tool + args + result), and
# `tool_execution_update`. For retrospective Langfuse eval we need exactly that
# message-level trace, never the token-by-token delta replay.
#
# Usage: read stdin (JSONL), drop message_update records, emit the rest.
#   session-filter.sh < stream.jsonl > clean.jsonl
#
# set -u: unset variables are treated as empty (permissive parse); unlike
# set -e this script must NOT die on a blank/odd line (read returns '' at EOF).
set -u
LINE=""
while IFS= read -r LINE; do
  # Skip any record whose top-level type is message_update (the delta replay).
  # Anchored to the FIRST key so nested `"type":"message_update"` inside a kept
  # record's content/args is never mismatched.
  if [[ "$LINE" != '{"type":"message_update"'* ]]; then
    printf '%s\n' "$LINE"
  fi
done