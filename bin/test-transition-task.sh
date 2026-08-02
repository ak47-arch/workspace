#!/usr/bin/env bash
# ============================================================================
# test-transition-task.sh — Test suite for bin/transition-task.sh
#
# Runs the script against isolated temp workspaces so no real workspace
# files are touched. Verifies:
#   - Task file updates (status, completed date, sessions, decisions)
#   - tasks.txt line movement across sections
#   - Error handling (invalid state, missing task file)
#   - Idempotency (re-running does not duplicate entries)
#   - Edge cases (sections at end of file, missing sections, no label)
#
# Usage:
#   bin/test-transition-task.sh          # run all tests
#   bin/test-transition-task.sh -v       # verbose (show script output)
# ============================================================================
set -uo pipefail

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/transition-task.sh"
VERBOSE=false
[ "${1:-}" = "-v" ] && VERBOSE=true

PASS=0
FAIL=0
FAILED_TESTS=()

# ─── Assertion helpers ─────────────────────────────────────────────────────
pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -Fq -- "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc — expected '$pattern' in $file"
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -Fq -- "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc — did not expect '$pattern' in $file"
  fi
}

assert_exit() {
  local expected="$1" actual="$2" desc="$3"
  if [ "$expected" -eq "$actual" ]; then
    pass "$desc"
  else
    fail "$desc — expected exit $expected, got $actual"
  fi
}

# ─── Fixture helpers ───────────────────────────────────────────────────────
# Create an isolated temp workspace with the script copied in
setup_workspace() {
  TMPROOT=$(mktemp -d)
  mkdir -p "$TMPROOT/bin" "$TMPROOT/docs/tasks" "$TMPROOT/docs/prd-queue" "$TMPROOT/docs/prd-archive"
  cp "$SCRIPT_PATH" "$TMPROOT/bin/"
}

teardown_workspace() {
  rm -rf "$TMPROOT"
}

# Default fixture task file (template from product-layer skill)
write_task_file() {
  cat > "$TMPROOT/docs/tasks/$1.md" <<EOF
# Task: $1

**Status**: in-prd
**Category**: Medium
**Project**: test-project
**Created**: 2026-08-01
**Source**: docs/tasks.txt — \`test task\`

## Artifacts

- Plan: _(will be created)_

## Sessions

- _(this session)_

## Decisions

- _(will be captured inline)_
EOF
}

write_tasks_txt() {
  cat > "$TMPROOT/docs/tasks.txt" <<'EOF'
tasks:
    # test fixture

    ## test-project

    ### Pending
    - test task [test-task]

    ## other-project

    ### Pending
    - other task
EOF
}

run_script() {
  if [ "$VERBOSE" = true ]; then
    "$TMPROOT/bin/transition-task.sh" "$@"
  else
    "$TMPROOT/bin/transition-task.sh" "$@" > /dev/null 2>&1
  fi
  return $?
}

UUID="019fbd12-7ea3-7152-9eec-f865cf69d6f7"
DEC1="sessions/$UUID/decisions/01-test-decision.md"
DEC2="sessions/$UUID/decisions/02-second-decision.md"

# ─── Tests ─────────────────────────────────────────────────────────────────

test_basic_complete() {
  echo "Test: basic complete transition with placeholders"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to complete --session "$UUID:planning" --decisions "$DEC1"
  local code=$?
  assert_exit 0 $code "script exits 0"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "**Status**: complete" "status updated to complete"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "**Completed**:" "completion date added"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [planning](../knowledge/sessions/$UUID/session.jsonl)" "session placeholder replaced"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [test-decision](../knowledge/sessions/$UUID/decisions/01-test-decision.md)" "decision placeholder replaced"
  assert_not_contains "$TMPROOT/docs/tasks/test-task.md" "_(this session)_" "session placeholder removed"
  assert_not_contains "$TMPROOT/docs/tasks/test-task.md" "_(will be captured inline)_" "decision placeholder removed"
  assert_contains "$TMPROOT/docs/tasks.txt" "    ### Complete" "Complete section present in tasks.txt"
  assert_contains "$TMPROOT/docs/tasks.txt" "(complete) test task [test-task]" "task line moved to Complete with prefix"
  teardown_workspace
}

test_multiple_decisions_end_of_file() {
  echo "Test: REGRESSION — multiple decisions with section at end of file"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to complete --session "$UUID:planning" --decisions "$DEC1,$DEC2"
  local code=$?
  assert_exit 0 $code "script exits 0 (no crash on second decision)"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [test-decision](../knowledge/sessions/$UUID/decisions/01-test-decision.md)" "first decision added"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [second-decision](../knowledge/sessions/$UUID/decisions/02-second-decision.md)" "second decision added"
  assert_contains "$TMPROOT/docs/tasks.txt" "(complete) test task [test-task]" "task line moved to Complete"
  teardown_workspace
}

test_append_to_existing_section_end_of_file() {
  echo "Test: append decision to existing section at end of file (no placeholder)"
  setup_workspace
  cat > "$TMPROOT/docs/tasks/test-task.md" <<EOF
# Task: test-task

**Status**: in-prd
**Category**: Medium
**Project**: test-project
**Created**: 2026-08-01
**Source**: docs/tasks.txt — \`test task\`

## Decisions

- [existing](../knowledge/sessions/$UUID/decisions/00-existing.md)
EOF
  write_tasks_txt

  run_script test-task --to complete --decisions "$DEC1"
  local code=$?
  assert_exit 0 $code "script exits 0 (append at end of file)"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [existing]" "existing decision preserved"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [test-decision]" "new decision appended"
  teardown_workspace
}

test_append_before_next_heading() {
  echo "Test: append decision to section in middle of file (heading follows)"
  setup_workspace
  cat > "$TMPROOT/docs/tasks/test-task.md" <<EOF
# Task: test-task

**Status**: in-prd
**Category**: Medium
**Project**: test-project
**Created**: 2026-08-01
**Source**: docs/tasks.txt — \`test task\`

## Decisions

- [existing](../knowledge/sessions/$UUID/decisions/00-existing.md)

## Further Notes

Nothing here.
EOF
  write_tasks_txt

  run_script test-task --to complete --decisions "$DEC1"
  local code=$?
  assert_exit 0 $code "script exits 0"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [test-decision]" "new decision appended"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "## Further Notes" "next heading preserved"
  teardown_workspace
}

test_prd_ready_no_completion_date() {
  echo "Test: transition to prd-ready (not complete) — no completion date"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to prd-ready --session "$UUID:planning"
  local code=$?
  assert_exit 0 $code "script exits 0"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "**Status**: prd-ready" "status updated to prd-ready"
  assert_not_contains "$TMPROOT/docs/tasks/test-task.md" "**Completed**" "no completion date for non-complete state"
  assert_contains "$TMPROOT/docs/tasks.txt" "    ### Queued" "Queued section present"
  assert_contains "$TMPROOT/docs/tasks.txt" "test task [test-task]" "task line moved to Queued"
  assert_not_contains "$TMPROOT/docs/tasks.txt" "(complete)" "no complete prefix in Queued"
  teardown_workspace
}

test_session_without_label() {
  echo "Test: session without label uses default 'session'"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to in-review --session "$UUID"
  local code=$?
  assert_exit 0 $code "script exits 0"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [session](../knowledge/sessions/$UUID/session.jsonl)" "default label used"
  teardown_workspace
}

test_create_missing_sections() {
  echo "Test: create Sessions and Decisions sections when absent"
  setup_workspace
  cat > "$TMPROOT/docs/tasks/test-task.md" <<'EOF'
# Task: test-task

**Status**: in-prd
**Category**: Medium
**Project**: test-project
**Created**: 2026-08-01
**Source**: docs/tasks.txt — `test task`

## Artifacts

- Plan: _(will be created)_
EOF
  write_tasks_txt

  run_script test-task --to in-progress --session "$UUID:implementation" --decisions "$DEC1"
  local code=$?
  assert_exit 0 $code "script exits 0"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "## Sessions" "Sessions section created"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [implementation]" "session link added"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "## Decisions" "Decisions section created"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [test-decision]" "decision link added"
  teardown_workspace
}

test_invalid_state() {
  echo "Test: invalid state is rejected"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to bogus
  local code=$?
  assert_exit 1 $code "script exits 1 for invalid state"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "**Status**: in-prd" "task file untouched"
  teardown_workspace
}

test_missing_task_file() {
  echo "Test: missing task file is an error"
  setup_workspace
  write_tasks_txt

  run_script nonexistent-task --to complete
  local code=$?
  assert_exit 1 $code "script exits 1 for missing task file"
  teardown_workspace
}

test_idempotent_rerun() {
  echo "Test: re-running does not duplicate entries"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to complete --session "$UUID:planning" --decisions "$DEC1"
  run_script test-task --to complete --session "$UUID:planning" --decisions "$DEC1"
  local code=$?
  assert_exit 0 $code "second run exits 0"
  local count
  count=$(grep -c -- "- \[test-decision\]" "$TMPROOT/docs/tasks/test-task.md" || true)
  assert_contains <(echo "count=$count") "count=1" "decision not duplicated on re-run"
  teardown_workspace
}

test_dry_run_no_changes() {
  echo "Test: dry-run makes no changes"
  setup_workspace
  write_task_file test-task
  write_tasks_txt
  cp "$TMPROOT/docs/tasks/test-task.md" "$TMPROOT/orig-task.md"
  cp "$TMPROOT/docs/tasks.txt" "$TMPROOT/orig-tasks.txt"

  run_script test-task --to complete --session "$UUID:planning" --decisions "$DEC1" --dry-run
  local code=$?
  assert_exit 0 $code "dry-run exits 0"
  if diff -q "$TMPROOT/orig-task.md" "$TMPROOT/docs/tasks/test-task.md" > /dev/null; then
    pass "task file unchanged in dry-run"
  else
    fail "task file changed in dry-run"
  fi
  if diff -q "$TMPROOT/orig-tasks.txt" "$TMPROOT/docs/tasks.txt" > /dev/null; then
    pass "tasks.txt unchanged in dry-run"
  else
    fail "tasks.txt changed in dry-run"
  fi
  teardown_workspace
}

test_prd_archive() {
  echo "Test: PRD archived on complete"
  setup_workspace
  write_task_file test-task
  write_tasks_txt
  touch "$TMPROOT/docs/prd-queue/2026-08-01-test-task.md"

  run_script test-task --to complete
  local code=$?
  assert_exit 0 $code "script exits 0"
  if [ -f "$TMPROOT/docs/prd-archive/2026-08-01-test-task.md" ]; then
    pass "PRD moved to archive"
  else
    fail "PRD not archived"
  fi
  if [ ! -f "$TMPROOT/docs/prd-queue/2026-08-01-test-task.md" ]; then
    pass "PRD removed from queue"
  else
    fail "PRD still in queue"
  fi
  teardown_workspace
}

test_special_chars_in_decision_path() {
  echo "Test: decision title with ampersand survives (sed escaping)"
  setup_workspace
  write_task_file test-task
  write_tasks_txt

  run_script test-task --to complete --decisions "sessions/$UUID/decisions/01-risk-&-reward.md"
  local code=$?
  assert_exit 0 $code "script exits 0"
  assert_contains "$TMPROOT/docs/tasks/test-task.md" "- [risk-&-reward](../knowledge/sessions/$UUID/decisions/01-risk-&-reward.md)" "link with & intact"
  teardown_workspace
}

# ─── Runner ────────────────────────────────────────────────────────────────
echo "=== transition-task.sh test suite ==="
echo "Script under test: $SCRIPT_PATH"
echo ""

test_basic_complete
test_multiple_decisions_end_of_file
test_append_to_existing_section_end_of_file
test_append_before_next_heading
test_prd_ready_no_completion_date
test_session_without_label
test_create_missing_sections
test_invalid_state
test_missing_task_file
test_idempotent_rerun
test_dry_run_no_changes
test_prd_archive
test_special_chars_in_decision_path

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
