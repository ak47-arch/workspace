#!/usr/bin/env bash
# ============================================================================
# transition-task.sh — Bookkeeping for task lifecycle transitions
#
# Usage:
#   bin/transition-task.sh <slug> --to <state> [--session <uuid:label>] [--decisions <files>] [--branch <name>] [--dry-run]
#
# Arguments:
#   <slug>                Task slug (e.g. "task-file-dashboard")
#   --to <state>          Target state: todo, in-prd, prd-ready, in-progress, in-review, complete
#   --session <uuid:label> Session UUID with optional label (e.g. "abc123:planning").
#                          Label is for auditability (planning, implementation, verification).
#                          Default label: "session"
#   --decisions <files>   Comma-separated decision file paths relative to docs/knowledge/
#                          (e.g. "sessions/<uuid>/decisions/01-foo.md")
#   --branch <name>       Commit the transition onto this task branch (created if missing)
#                          instead of the current branch. Keeps lifecycle bookkeeping in the
#                          same PR stream as the implementation (one PR per task).
#   --workspace <root>    Operate on a different repo root than the script's own (the task
#                          worktree clone) so transitions commit under the same branch as the
#                          implementation. Default: this script's parent repo.
#   --dry-run             Print what would be done without making changes
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
#      - All links are clickable markdown links with proper relative paths
#   2. Moves the task line in docs/tasks.txt to the correct status section
#   3. Archives the PRD from docs/prd-queue/ to docs/prd-archive/ (if complete)
#   4. Commits everything
# ============================================================================
set -euo pipefail

# ─── Helpers ───────────────────────────────────────────────────────────────
# Replace first occurrence of a placeholder with literal text (robust against
# special characters like &, \, and | that would break sed/awk replacements)
replace_placeholder() {
  local file="$1" placeholder="$2" replacement="$3"
  python3 - "$file" "$placeholder" "$replacement" <<'PYEOF'
import sys
path, placeholder, replacement = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8') as f:
    content = f.read()
if placeholder in content:
    content = content.replace(placeholder, replacement, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
PYEOF
}

# Validate UUID format (8-4-4-4-12 hex)
is_valid_uuid() {
  echo "$1" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
}

# ─── Parse arguments ───────────────────────────────────────────────────────
if [ $# -lt 3 ]; then
  echo "Usage: $(basename "$0") <slug> --to <state> [--session <uuid:label>] [--decisions <files>] [--dry-run]"
  echo "States: in-prd, prd-ready, in-progress, in-review, complete"
  echo "Session label examples: 'abc123:planning', 'def456:implementation', 'ghi789:verification'"
  exit 1
fi

SLUG="$1"
shift
TARGET_STATE=""
TASK_BRANCH=""
WORKSPACE_OVERRIDE=""
SESSION_UUID=""
DECISIONS=""
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --to) TARGET_STATE="$2"; shift 2 ;;
    --session) SESSION_UUID="$2"; shift 2 ;;
    --decisions) DECISIONS="$2"; shift 2 ;;
    --branch) TASK_BRANCH="$2"; shift 2 ;;
    --workspace) WORKSPACE_OVERRIDE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
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

# ─── Resolve paths ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="${WORKSPACE_OVERRIDE:-$SCRIPT_DIR}"
TASK_MD="$WORKSPACE/docs/tasks/$SLUG.md"
TASKS_TXT="$WORKSPACE/docs/tasks.txt"
PRD_QUEUE="$WORKSPACE/docs/prd-queue"
PRD_ARCHIVE="$WORKSPACE/docs/prd-archive"

# ─── Validate slug / task file ─────────────────────────────────────────────
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

# ─── Validate session UUID format (if provided) ────────────────────────────
if [ -n "$SESSION_UUID" ]; then
  SESSION_ID="${SESSION_UUID%%:*}"
  SESSION_LABEL="${SESSION_UUID#*:}"
  # If there's no colon separator, the label equals the UUID (use default)
  if [ "$SESSION_LABEL" = "$SESSION_ID" ]; then
    SESSION_LABEL="session"
  fi
  if ! is_valid_uuid "$SESSION_ID"; then
    echo "Warning: Session ID '$SESSION_ID' does not look like a valid UUID"
    echo "  (expected format: 8-4-4-4-12 hex, e.g. 019fbd12-7ea3-7152-9eec-f865cf69d6f7)"
  fi
fi

# ─── Dry-run mode creates working copies in a temp dir ─────────────────────
if [ "$DRY_RUN" = true ]; then
  TMPDIR=$(mktemp -d)
  cp "$TASK_MD" "$TMPDIR/task.md"
  TASK_MD="$TMPDIR/task.md"
  cp "$TASKS_TXT" "$TMPDIR/tasks.txt"
  TASKS_TXT="$TMPDIR/tasks.txt"
  echo "  [dry-run] Working copies in $TMPDIR"
fi

# ─── Update task file ──────────────────────────────────────────────────────
# Update status
sed -i "s/^\*\*Status\*\*:.*/**Status**: $TARGET_STATE/" "$TASK_MD"

# If complete, add/update completion date
if [ "$TARGET_STATE" = "complete" ]; then
  TODAY=$(date '+%Y-%m-%d %H:%M')
  if grep -q '^\*\*Completed\*\*:' "$TASK_MD"; then
    sed -i "s/^\*\*Completed\*\*:.*/**Completed**: $TODAY/" "$TASK_MD"
  else
    sed -i "/^\*\*Status\*\*:.*/a **Completed**: $TODAY" "$TASK_MD"
  fi
fi

# Append session (replaces placeholder if present, generates clickable link)
if [ -n "$SESSION_UUID" ]; then
  SESSION_LINK="- [$SESSION_LABEL](../knowledge/sessions/$SESSION_ID/session.jsonl)"

  if grep -q "^## Sessions" "$TASK_MD"; then
    if ! grep -Fq "$SESSION_ID" "$TASK_MD"; then
      if grep -q -- "- _(this session)_" "$TASK_MD"; then
        replace_placeholder "$TASK_MD" "- _(this session)_" "$SESSION_LINK"
        echo "  Replaced session placeholder"
      else
        LINE_NUM=$(grep -n "^## Sessions" "$TASK_MD" | head -1 | cut -d: -f1)
        NEXT_HEADING=$(sed -n "$((LINE_NUM+1)),\$p" "$TASK_MD" | grep -n "^## " | head -1 | cut -d: -f1 || true)
        if [ -n "$NEXT_HEADING" ]; then
          INSERT_AT=$((LINE_NUM + NEXT_HEADING - 1))
          sed -i "$((INSERT_AT-1))a $SESSION_LINK" "$TASK_MD"
        else
          echo "$SESSION_LINK" >> "$TASK_MD"
        fi
        echo "  Appended session"
      fi
    fi
  else
    printf "\n## Sessions\n\n%s\n" "$SESSION_LINK" >> "$TASK_MD"
    echo "  Created Sessions section"
  fi
fi

# Append decisions (replaces placeholder if present, generates clickable links)
if [ -n "$DECISIONS" ]; then
  IFS=',' read -ra DEC_ARRAY <<< "$DECISIONS"
  for DEC in "${DEC_ARRAY[@]}"; do
    DEC_TRIMMED=$(echo "$DEC" | xargs)
    # Extract title from filename (e.g. "01-foo-bar.md" -> "foo-bar")
    DEC_FILENAME=$(basename "$DEC_TRIMMED" .md)
    DEC_TITLE=$(echo "$DEC_FILENAME" | sed 's/^[0-9]*-//')
    DEC_LINK="- [$DEC_TITLE](../knowledge/$DEC_TRIMMED)"

    if grep -q "^## Decisions" "$TASK_MD"; then
      if ! grep -Fq "$DEC_TRIMMED" "$TASK_MD"; then
        if grep -q -- "- _(will be captured inline)_" "$TASK_MD"; then
          replace_placeholder "$TASK_MD" "- _(will be captured inline)_" "$DEC_LINK"
          echo "  Replaced decision placeholder"
        else
          LINE_NUM=$(grep -n "^## Decisions" "$TASK_MD" | head -1 | cut -d: -f1)
          NEXT_HEADING=$(sed -n "$((LINE_NUM+1)),\$p" "$TASK_MD" | grep -n "^## " | head -1 | cut -d: -f1 || true)
          if [ -n "$NEXT_HEADING" ]; then
            INSERT_AT=$((LINE_NUM + NEXT_HEADING - 1))
            sed -i "$((INSERT_AT-1))a $DEC_LINK" "$TASK_MD"
          else
            echo "$DEC_LINK" >> "$TASK_MD"
          fi
          echo "  Appended decision"
        fi
      fi
    else
      printf "\n## Decisions\n\n%s\n" "$DEC_LINK" >> "$TASK_MD"
      echo "  Created Decisions section"
    fi
  done
  echo "  Updated decisions"
fi

# ─── Also convert any existing backtick-wrapped paths to clickable links ───
# Converts: "- Plan: \`docs/prd-archive/foo.md\`" -> "- [Plan](../prd-archive/foo.md)"
if grep -q '^[-*] .*: \`docs/' "$TASK_MD"; then
  sed -i 's/^\([-*] \)\([^:]*\): \`docs\/\([^`]*\)\`/\1[\2](..\/\3)/' "$TASK_MD"
  echo "  Converted backtick paths to clickable links in artifacts"
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

# ─── Collect ALL lines annotated with [slug] ───────────────────────────────
# Each is paired with the project section it currently lives in, so a merged
# bundle can move every line to its OWN project's target status section
# (lines under "## all" stay under "## all").
def project_of(lines, idx):
    """Return the enclosing project section name for line index idx."""
    proj = None
    for i in range(idx + 1):
        m = re.match(r'^    ## (.+)', lines[i])
        if m:
            proj = m.group(1).strip()
    return proj

slug_items = []  # (verbatim line, project section)
for i, line in enumerate(lines):
    if f'[{slug}]' in line:
        proj = project_of(lines, i)
        if proj is None:
            proj = project  # fall back to the task file's declared project
        slug_items.append((line, proj))

if not slug_items:
    print(f"Warning: Could not find line containing [{slug}] in tasks.txt")
    print("Skipping tasks.txt update.")
    exit(0)

# ─── Remove every slug line (original positions no longer matter) ─────────
new_lines = [l for l in lines if f'[{slug}]' not in l]

# ─── Relocate each slug line into its own project's target status section ──
section_order = {'Pending': 0, 'Queued': 1, 'Complete': 2}
single_line = len(slug_items) == 1

for slug_line, line_project in slug_items:
    # Single-line tasks keep the legacy behaviour: use the task file's
    # declared project (not the line's current section). Multi-line bundles
    # use each line's own project so lines stay under their own project.
    target_project = project if single_line else line_project

    # Normalize the slug line
    normalized_line = slug_line
    if not normalized_line.startswith('    '):
        normalized_line = '    ' + normalized_line

    # Ensure the line has (complete) prefix if moving to Complete
    if target_section == 'Complete' and '(complete)' not in normalized_line:
        normalized_line = re.sub(r'^(\s*-\s*)', r'\1(complete) ', normalized_line)

    # Find the project section
    project_start = None
    for i, line in enumerate(new_lines):
        m = re.match(r'^    ## (.+)', line)
        if m and m.group(1).strip() == target_project:
            project_start = i
            break

    if project_start is None:
        print(f"Warning: Could not find project section '## {target_project}' in tasks.txt")
        continue

    # Find the end of the project section (next ## or end of file)
    project_end = len(new_lines)
    for i in range(project_start + 1, len(new_lines)):
        if re.match(r'^    ## ', new_lines[i]):
            project_end = i
            break

    # Look for ### <target_section> within this project
    status_idx = None
    for i in range(project_start, project_end):
        m = re.match(r'^    ### (.+)', new_lines[i])
        if m and m.group(1).strip() == target_section:
            status_idx = i
            break

    if status_idx is not None:
        # Insert after the last line in this status section
        insert_after = status_idx
        for i in range(status_idx + 1, project_end):
            if re.match(r'^    (###|##) ', new_lines[i]):
                break
            if new_lines[i].strip():
                insert_after = i
        new_lines.insert(insert_after + 1, normalized_line)
        print(f"  Added line to {target_project} / {target_section}")
    else:
        # Create the status section in the right order
        target_order = section_order.get(target_section, 99)

        existing_sections = []
        for i in range(project_start, project_end):
            m = re.match(r'^    ### (.+)', new_lines[i])
            if m:
                sec = m.group(1).strip()
                order = section_order.get(sec, 99)
                existing_sections.append((i, sec, order))

        insert_at = project_end
        for i, sec, order in existing_sections:
            if order > target_order:
                insert_at = i
                break

        new_lines.insert(insert_at, f'    ### {target_section}')
        new_lines.insert(insert_at + 1, normalized_line)
        print(f"  Created {target_section} section under {target_project}")

with open(tasks_txt, 'w') as f:
    f.write('\n'.join(new_lines))

print("  tasks.txt updated")
PYEOF

# ─── Archive PRD (if complete) ─────────────────────────────────────────────
if [ "$TARGET_STATE" = "complete" ]; then
  PRD_FILE=$(ls "$PRD_QUEUE/"*-"$SLUG.md" 2>/dev/null | head -1 || true)
  if [ -n "$PRD_FILE" ] && [ -f "$PRD_FILE" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  [dry-run] Would archive PRD: $(basename "$PRD_FILE")"
    else
      mv "$PRD_FILE" "$PRD_ARCHIVE/"
      echo "  Archived PRD: $(basename "$PRD_FILE")"
    fi
  fi
fi

# ─── Commit ────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] Would commit: task($SLUG): transition to $TARGET_STATE"
  echo "  [dry-run] Temp files in $TMPDIR — inspect them to verify correctness"
  echo "Done (dry-run)."
  exit 0
fi

cd "$WORKSPACE"

# Check that we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Warning: Not a git repository. Skipping commit."
  exit 0
fi

# One-PR-per-task invariant: when a task branch is supplied, commit the
# transition onto that branch (created if missing) so lifecycle bookkeeping and
# the implementation land in the same PR stream — never on a protected default
# branch where they'd be stranded from the PR diff.
current_branch="$(git branch --show-current 2>/dev/null || echo 'branch-unavailable')"
if [ -n "$TASK_BRANCH" ] && [ "$current_branch" != "$TASK_BRANCH" ]; then
  if ! git rev-parse --verify "refs/heads/$TASK_BRANCH" >/dev/null 2>&1; then
    echo "  [transition] creating task branch '$TASK_BRANCH' from current HEAD" >&2
    git branch "$TASK_BRANCH";
  fi
  echo "  [transition] checking out task branch '$TASK_BRANCH'" >&2
  git checkout "$TASK_BRANCH"
fi

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