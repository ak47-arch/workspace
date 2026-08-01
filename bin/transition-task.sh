#!/usr/bin/env bash
# ============================================================================
# transition-task.sh — Bookkeeping for task lifecycle transitions
#
# Usage:
#   bin/transition-task.sh <slug> --to <state> [--session <uuid>] [--decisions <files>]
#
# Arguments:
#   <slug>                Task slug (e.g. "task-file-dashboard")
#   --to <state>          Target state: in-prd, prd-ready, in-progress, in-review, complete
#   --session <uuid>      Session UUID to append to the task file (optional)
#   --decisions <files>   Comma-separated decision file paths relative to docs/knowledge/
#                         (optional)
#
# States:
#   in-prd       → Being planned, stays in Pending
#   prd-ready    → Plan done, moves to Queued
#   in-progress  → Being implemented, stays in Queued
#   in-review    → Being verified, stays in Queued
#   complete     → Done, moves to Complete
#
# What it does:
#   1. Updates docs/tasks/<slug>.md (status, sessions, decisions, completion date)
#   2. Moves the task line in docs/tasks.txt to the correct status section
#   3. Archives the PRD from docs/prd-queue/ to docs/prd-archive/ (if complete)
#   4. Commits everything
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$SCRIPT_DIR"
TASK_FILE="$WORKSPACE/docs/tasks"
TASKS_TXT="$WORKSPACE/docs/tasks.txt"
PRD_QUEUE="$WORKSPACE/docs/prd-queue"
PRD_ARCHIVE="$WORKSPACE/docs/prd-archive"

# ─── Parse arguments ───────────────────────────────────────────────────────
if [ $# -lt 3 ]; then
  echo "Usage: $(basename "$0") <slug> --to <state> [--session <uuid>] [--decisions <files>]"
  echo "States: in-prd, prd-ready, in-progress, in-review, complete"
  exit 1
fi

SLUG="$1"
shift
TARGET_STATE=""
SESSION_UUID=""
DECISIONS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --to) TARGET_STATE="$2"; shift 2 ;;
    --session) SESSION_UUID="$2"; shift 2 ;;
    --decisions) DECISIONS="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate state
VALID_STATES="in-prd prd-ready in-progress in-review complete"
FOUND=0
for s in $VALID_STATES; do
  if [ "$s" = "$TARGET_STATE" ]; then FOUND=1; break; fi
done
if [ "$FOUND" -eq 0 ]; then
  echo "Error: Invalid state '$TARGET_STATE'. Must be one of: $VALID_STATES"
  exit 1
fi

# Map state to tasks.txt section
STATE_TO_SECTION="in-prd=Pending
prd-ready=Queued
in-progress=Queued
in-review=Queued
complete=Complete"

STATUS_SECTION=""
while IFS='=' read -r state section; do
  if [ "$state" = "$TARGET_STATE" ]; then
    STATUS_SECTION="$section"
    break
  fi
done <<< "$STATE_TO_SECTION"

# ─── Validate slug ─────────────────────────────────────────────────────────
TASK_MD="$TASK_FILE/$SLUG.md"
if [ ! -f "$TASK_MD" ]; then
  echo "Error: Task file not found: $TASK_MD"
  exit 1
fi

# ─── Extract project from task file ────────────────────────────────────────
PROJECT=$(grep -m1 '^\*\*Project\*\*:' "$TASK_MD" | sed 's/^\*\*Project\*\*: *//')
if [ -z "$PROJECT" ]; then
  echo "Error: Could not determine project from task file $TASK_MD"
  exit 1
fi

# ─── Update task file ──────────────────────────────────────────────────────
# Update status
sed -i "s/^\*\*Status\*\*:.*/**Status**: $TARGET_STATE/" "$TASK_MD"

# If complete, add/update completion date
if [ "$TARGET_STATE" = "complete" ]; then
  TODAY=$(date +%Y-%m-%d)
  if grep -q '^\*\*Completed\*\*:' "$TASK_MD"; then
    sed -i "s/^\*\*Completed\*\*:.*/**Completed**: $TODAY/" "$TASK_MD"
  else
    sed -i "/^\*\*Status\*\*:.*/a **Completed**: $TODAY" "$TASK_MD"
  fi
fi

# Append session (replaces placeholder if present)
if [ -n "$SESSION_UUID" ]; then
  SESSION_LINE="- \`$SESSION_UUID\`"
  if grep -q "^## Sessions" "$TASK_MD"; then
    if ! grep -q "$SESSION_UUID" "$TASK_MD"; then
      if grep -q -- "- _(this session)_" "$TASK_MD"; then
        sed -i "s|- _(this session)_|$SESSION_LINE|" "$TASK_MD"
        echo "  Replaced session placeholder"
      else
        LINE_NUM=$(grep -n "^## Sessions" "$TASK_MD" | head -1 | cut -d: -f1)
        NEXT_HEADING=$(sed -n "$((LINE_NUM+1)),\$p" "$TASK_MD" | grep -n "^## " | head -1 | cut -d: -f1)
        if [ -n "$NEXT_HEADING" ]; then
          INSERT_AT=$((LINE_NUM + NEXT_HEADING - 1))
          sed -i "$((INSERT_AT-1))a $SESSION_LINE" "$TASK_MD"
        else
          echo "$SESSION_LINE" >> "$TASK_MD"
        fi
        echo "  Appended session"
      fi
    fi
  else
    printf "\n## Sessions\n\n%s\n" "$SESSION_LINE" >> "$TASK_MD"
    echo "  Created Sessions section"
  fi
fi

# Append decisions
if [ -n "$DECISIONS" ]; then
  IFS=',' read -ra DEC_ARRAY <<< "$DECISIONS"
  for DEC in "${DEC_ARRAY[@]}"; do
    DEC_TRIMMED=$(echo "$DEC" | xargs)
    DEC_LINE="- $DEC_TRIMMED"
    if grep -q "^## Decisions" "$TASK_MD"; then
      if ! grep -q "$DEC_TRIMMED" "$TASK_MD"; then
        if grep -q -- "- _(will be captured inline)_" "$TASK_MD"; then
          sed -i "s|- _(will be captured inline)_|$DEC_LINE|" "$TASK_MD"
        else
          LINE_NUM=$(grep -n "^## Decisions" "$TASK_MD" | head -1 | cut -d: -f1)
          NEXT_HEADING=$(sed -n "$((LINE_NUM+1)),\$p" "$TASK_MD" | grep -n "^## " | head -1 | cut -d: -f1)
          if [ -n "$NEXT_HEADING" ]; then
            INSERT_AT=$((LINE_NUM + NEXT_HEADING - 1))
            sed -i "$((INSERT_AT-1))a $DEC_LINE" "$TASK_MD"
          else
            echo "$DEC_LINE" >> "$TASK_MD"
          fi
        fi
      fi
    else
      printf "\n## Decisions\n\n%s\n" "$DEC_LINE" >> "$TASK_MD"
    fi
  done
  echo "  Updated decisions"
fi

# ─── Update tasks.txt ──────────────────────────────────────────────────────
# Use Python for reliable text manipulation
python3 << PYEOF
import re
import os

slug = "$SLUG"
project = "$PROJECT"
target_section = "$STATUS_SECTION"
tasks_txt = "$TASKS_TXT"

with open(tasks_txt, 'r') as f:
    content = f.read()
    lines = content.split('\n')

# Find the line containing [slug]
slug_line_idx = None
slug_line = None
for i, line in enumerate(lines):
    if f'[{slug}]' in line:
        slug_line_idx = i
        slug_line = line
        break

if slug_line_idx is None:
    print(f"Warning: Could not find line containing [{slug}] in tasks.txt")
    print("Skipping tasks.txt update.")
    exit(0)

# Remove the slug line from its current position
del lines[slug_line_idx]

# Find the project section
project_start = None
for i, line in enumerate(lines):
    m = re.match(r'^    ## (.+)', line)
    if m and m.group(1).strip() == project:
        project_start = i
        break

if project_start is None:
    print(f"Warning: Could not find project section '## {project}' in tasks.txt")
    print("Skipping tasks.txt update.")
    with open(tasks_txt, 'w') as f:
        f.write('\n'.join(lines))
    exit(0)

# Find the end of the project section (next ## or end of file)
project_end = len(lines)
for i in range(project_start + 1, len(lines)):
    if re.match(r'^    ## ', lines[i]):
        project_end = i
        break

# Normalize the slug line
normalized_line = slug_line
if not normalized_line.startswith('    '):
    normalized_line = '    ' + normalized_line

# Ensure the line has (complete) prefix if moving to Complete
if target_section == 'Complete' and '(complete)' not in normalized_line:
    normalized_line = re.sub(r'^(\s*-\s*)', r'\1(complete) ', normalized_line)

# Look for ### <target_section> within this project
status_idx = None
for i in range(project_start, project_end):
    m = re.match(r'^    ### (.+)', lines[i])
    if m and m.group(1).strip() == target_section:
        status_idx = i
        break

if status_idx is not None:
    # Insert after the last line in this status section
    insert_after = status_idx
    for i in range(status_idx + 1, project_end):
        if re.match(r'^    (###|##) ', lines[i]):
            break
        if lines[i].strip():
            insert_after = i
    lines.insert(insert_after + 1, normalized_line)
    print(f"  Added line to {project} / {target_section}")
else:
    # Create the status section in the right order
    section_order = {'Pending': 0, 'Queued': 1, 'Complete': 2}
    target_order = section_order.get(target_section, 99)

    existing_sections = []
    for i in range(project_start, project_end):
        m = re.match(r'^    ### (.+)', lines[i])
        if m:
            sec = m.group(1).strip()
            order = section_order.get(sec, 99)
            existing_sections.append((i, sec, order))

    insert_at = project_end
    for i, sec, order in existing_sections:
        if order > target_order:
            insert_at = i
            break

    new_lines = [f'    ### {target_section}', normalized_line]
    for j, nl in enumerate(new_lines):
        lines.insert(insert_at + j, nl)
    print(f"  Created {target_section} section under {project}")

with open(tasks_txt, 'w') as f:
    f.write('\n'.join(lines))

print("  tasks.txt updated")
PYEOF

# ─── Archive PRD (if complete) ─────────────────────────────────────────────
if [ "$TARGET_STATE" = "complete" ]; then
  PRD_FILE=$(ls "$PRD_QUEUE/"*-"$SLUG.md" 2>/dev/null | head -1 || true)
  if [ -n "$PRD_FILE" ] && [ -f "$PRD_FILE" ]; then
    mv "$PRD_FILE" "$PRD_ARCHIVE/"
    echo "  Archived PRD: $(basename "$PRD_FILE")"
  fi
fi

# ─── Commit ────────────────────────────────────────────────────────────────
cd "$WORKSPACE"

git add docs/tasks/"$SLUG.md" docs/tasks.txt docs/prd-queue/ docs/prd-archive/ 2>/dev/null || true

if git diff --cached --quiet; then
  echo "  No changes to commit."
else
  git commit -m "task($SLUG): transition to $TARGET_STATE

- Update task file status, sessions, decisions
- Move task in tasks.txt to $STATUS_SECTION
- Archive PRD (if applicable)"
  echo "  Committed."
fi

echo "Done."