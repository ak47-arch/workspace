#!/usr/bin/env bash
# ============================================================================
# backfill-timestamps.sh — One-time backfill of minute-precision timestamps
#
# Updates all existing decision files, task files, and PRD files from
# day-precision dates (yyyy-mm-dd) to minute-precision timestamps
# (yyyy-mm-dd HH:MM) using git commit timestamps as the source of truth.
#
# Usage: bash bin/backfill-timestamps.sh
# Run from workspace root.
# ============================================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "/home/anupam/Desktop/workspace")"

echo "=== Backfilling timestamps from git history ==="

# ─── Helper: get the creation commit timestamp for a file ────────────────
# Returns yyyy-mm-dd HH:MM (local timezone)
get_creation_time() {
  local file="$1"
  # Get the oldest commit that touched this file (the creation)
  local ts
  ts=$(git log --follow --format="%ad" --date=format:"%Y-%m-%d %H:%M" -- "$file" 2>/dev/null | tail -1) || true
  if [ -z "$ts" ]; then
    echo ""
    return 0
  fi
  echo "$ts"
}

# ─── 1. Decision files ───────────────────────────────────────────────────
echo ""
echo "--- Decision files ---"
UPDATED=0
SKIPPED=0
for f in docs/knowledge/sessions/*/decisions/*.md; do
  [ -f "$f" ] || continue

  # Handle both "**Date**: yyyy-mm-dd" and "Date: yyyy-mm-dd" (legacy)
  # First try bold format
  CURRENT_DATE=$(grep -m1 '^\*\*Date\*\*: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$' "$f" | sed 's/^\*\*Date\*\*: //' || true)
  FORMAT="bold"
  if [ -z "$CURRENT_DATE" ]; then
    # Try legacy format
    CURRENT_DATE=$(grep -m1 '^Date: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$' "$f" | sed 's/^Date: //' || true)
    FORMAT="legacy"
  fi
  # Skip if already has time component
  if echo "$CURRENT_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'; then
    echo "  [skip] $f — already has time precision"
    continue
  fi

  if [ -z "$CURRENT_DATE" ]; then
    echo "  [skip] $f — no Date field found"
    continue
  fi

  NEW_TIME=$(get_creation_time "$f")
  if [ -z "$NEW_TIME" ]; then
    echo "  [skip] $f — could not determine git timestamp"
    continue
  fi

  if [ "$FORMAT" = "bold" ]; then
    sed -i "s/^\*\*Date\*\*: $CURRENT_DATE/**Date**: $NEW_TIME/" "$f"
  else
    sed -i "s/^Date: $CURRENT_DATE/Date: $NEW_TIME/" "$f"
  fi
  echo "  [ok]   $f — $CURRENT_DATE → $NEW_TIME"
  UPDATED=$((UPDATED + 1))
done
echo "  Updated: $UPDATED files"

# ─── 2. Task files ───────────────────────────────────────────────────────
echo ""
echo "--- Task files ---"
UPDATED=0
for f in docs/tasks/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  [ "$BASENAME" = "README.md" ] && continue

  # Update **Created**: yyyy-mm-dd
  for FIELD in "Created" "Completed"; do
    CURRENT_DATE=$(grep -m1 "^\*\*$FIELD\*\*: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" "$f" | sed "s/^\*\*$FIELD\*\*: //" || true)
    if [ -z "$CURRENT_DATE" ]; then
      continue
    fi
    # Skip if already has time
    if echo "$CURRENT_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'; then
      continue
    fi

    NEW_TIME=$(get_creation_time "$f")
    if [ -z "$NEW_TIME" ]; then
      echo "  [skip] $f — could not determine git timestamp"
      continue
    fi

    sed -i "s/^\*\*$FIELD\*\*: $CURRENT_DATE/**$FIELD**: $NEW_TIME/" "$f"
    echo "  [ok]   $f — $FIELD: $CURRENT_DATE → $NEW_TIME"
    UPDATED=$((UPDATED + 1))
  done
done
echo "  Updated: $UPDATED fields"

# ─── 3. PRD files ────────────────────────────────────────────────────────
echo ""
echo "--- PRD files ---"
UPDATED=0
for f in docs/prd/*.md; do
  [ -f "$f" ] || continue

  CURRENT_DATE=$(grep -m1 '^\*\*Date\*\*: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$' "$f" | sed 's/^\*\*Date\*\*: //' || true)
  if [ -z "$CURRENT_DATE" ]; then
    continue
  fi
  if echo "$CURRENT_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'; then
    continue
  fi

  NEW_TIME=$(get_creation_time "$f")
  if [ -z "$NEW_TIME" ]; then
    echo "  [skip] $f — could not determine git timestamp"
    continue
  fi

  sed -i "s/^\*\*Date\*\*: $CURRENT_DATE/**Date**: $NEW_TIME/" "$f"
  echo "  [ok]   $f — $CURRENT_DATE → $NEW_TIME"
  UPDATED=$((UPDATED + 1))
done
echo "  Updated: $UPDATED files"

echo ""
echo "=== Done ==="