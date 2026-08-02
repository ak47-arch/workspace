## Decision: Reliable Lifecycle Transition Script with Test Suite

**Status**: accepted
**Date**: 2026-08-02 21:41
**Task**: combine-factory-context-factory-txt
**Project**: software-factory
**Session**: sessions/019fbd12-7ea3-7152-9eec-f865cf69d6f7/session.jsonl

### Context

The `bin/transition-task.sh` script is the single point of lifecycle bookkeeping for all tasks. It is called by the product-layer skill and potentially by future assembly-line skills. A crash was discovered during its first real use: when appending a second decision to a task file where the Decisions section was the last section (no heading after it), the script crashed with exit code 1 due to a `set -euo pipefail` + `grep` mismatch interaction.

### Problem

The script had three reliability issues:
1. **Pipefail crash**: `NEXT_HEADING=$(sed ... | grep -n "^## " | head -1 | cut -d: -f1)` — when the section is at end of file, `grep` finds no match and exits 1. With `set -o pipefail`, the pipeline exits 1. With `set -e`, the script aborts before updating tasks.txt or committing.
2. **Sed replacement injection**: `sed -i "s|...|$USER_DATA|"` — `$USER_DATA` (session links, decision links) could contain `&` (interpreted as "matched text") or `\` (escape), corrupting the replacement.
3. **No testability**: No way to verify correctness without running against real workspace files. No `--dry-run` mode.

### Alternatives

- **Patch just the pipefail bug** — fix the immediate crash but leave the sed injection and testability gaps. Rejected because the script is a critical path in the SDLC pipeline — it needs to be reliable, not just not-crashing.
- **Rewrite in Python entirely** — complete control but would break the pattern of bash-skills-calling-bash tools. The Python heredoc pattern already handles the tasks.txt manipulation; task file manipulation could follow but would be a larger refactor.
- **Fix all three issues + add tests** — chosen.

### Decision

1. Add `|| true` to both `NEXT_HEADING` command substitutions (sessions and decisions branches) so `grep` finding no heading doesn't trip `set -e`.
2. Replace `sed` placeholder replacement with `python3.replace()` calls — literal string replacement, no special character interpretation.
3. Use `grep -Fq` (fixed string) instead of `grep -q` (regex) for matching session IDs and decision paths.
4. Add `--dry-run` mode that copies files to a temp dir and reports what would be done without modifying real files.
5. Add UUID format validation for `--session` argument with a warning if the format is suspect.
6. Add git repository check before attempting commit.
7. Create `bin/test-transition-task.sh` with 13 tests covering all code paths, including the regression (multiple decisions, section at end of file), edge cases (missing sections, invalid state, dry-run, special characters), and idempotency.

### Rationale

- The pipefail crash is the most damaging bug — it silently leaves the task lifecycle in an inconsistent state (task file updated but tasks.txt not). Fixing it is the highest priority.
- The sed injection bug is latent but real — it would corrupt the task file if a decision title or session label contained `&` or `\`. Using python for literal replacement eliminates this class of bug entirely.
- The test suite is not optional: the script is the bookkeeping backbone for the entire task lifecycle. Without tests, every future modification risks regression. 45 assertions across 13 tests cover the full surface area.
- `--dry-run` enables safe verification before running against real workspace files, and also serves as a debugging tool for test authors.

### Consequences

- `bin/transition-task.sh` is now 488 lines of test code + 320 lines of script.
- `bin/test-transition-task.sh` is a standalone test runner that creates isolated temp workspaces (no git repo needed).
- The script now depends on `python3` for task file manipulation (already depended on it for tasks.txt).
- The `--dry-run` flag is documented in the script's usage header.
- The test suite can be run at any time: `bin/test-transition-task.sh` (or `-v` for verbose).
- Future modifications to the script must not break the tests — CI could run them as a pre-commit step.

### Revision triggers

- If the task file format changes (new sections, different field names) — the script's sed patterns and test fixtures need updating.
- If the tasks.txt format changes (different indentation, section headers) — the Python heredoc and test fixtures need updating.
- If the factory grows to need a real task management system (database, API) — the script and tests should be deprecated in favor of the new system.
- If the `set -euo pipefail` pattern proves too brittle for this script — consider switching to explicit error handling throughout.