#!/usr/bin/env bash
# sanitize-session.sh — redact known secret patterns from a pi session trace
# (JSONL) so knowledge-base snapshots never carry live credentials.
#
# Why: the save-knowledge workflow copies session.jsonl verbatim, and sessions
# capture tool output (e.g. `cat ~/.config/gh/hosts.yml`, env vars) that can
# embed API keys / OAuth tokens. Committing those trips GitHub Push Protection
# (GH013) and blocks the knowledge save. This runs BEFORE the copy lands in
# docs/knowledge/.
#
# Patterns redacted (value → REDACTED, prefix kept for readability):
#   sk-or-v1-*        OpenRouter API keys
#   gho_*             GitHub OAuth tokens (gh hosts.yml)
#   ghp_*             GitHub classic PATs
#   github_pat_*      GitHub fine-grained PATs
#   xoxb-/xoxp-*      Slack tokens
#   AKIA*             AWS access key ids
#
# Usage:
#   bin/sanitize-session.sh <session.jsonl> [--dry-run]
#   --dry-run   Print what would change without modifying the file.
#
# Exit codes: 0 success (or dry-run) · 2 usage · 3 nothing to do.
set -u

DRY_RUN=false
FILE=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) echo "Usage: bin/sanitize-session.sh <file> [--dry-run]"; exit 0 ;;
    *) FILE="$a" ;;
  esac
done
if [ -z "$FILE" ]; then echo "ERROR: missing <file>" >&2; exit 2; fi
if [ ! -f "$FILE" ]; then echo "ERROR: not a file: $FILE" >&2; exit 2; fi

# One sed pass over the whole file. Prefixes survive; the value becomes REDACTED.
# Longest-first alternation so fine-grained PATs match before the bare ghp_ case.
SED_PROG=(
  -E
  -e 's/(github_pat_)[A-Za-z0-9_]{20,}/\1REDACTED/g'
  -e 's/(sk-or-v1-)[A-Za-z0-9_-]{20,}/\1REDACTED/g'
  -e 's/(gho_)[A-Za-z0-9]{20,}/\1REDACTED/g'
  -e 's/(ghp_)[A-Za-z0-9]{20,}/\1REDACTED/g'
  -e 's/(xox[abprs]-)[A-Za-z0-9-]{10,}/\1REDACTED/g'
  -e 's/(AKIA)[A-Z0-9]{16}/\1REDACTED/g'
)

if [ "$DRY_RUN" = true ]; then
  # Count matches in a copy without touching the original.
  MATCHES=$(sed "${SED_PROG[@]}" "$FILE" | grep -cE "REDACTED" || true)
  echo "  [dry-run] $FILE: $MATCHES redactions would apply" >&2
  exit 0
fi

sed -i "${SED_PROG[@]}" "$FILE"
# Verify nothing redacted-looking remains unredacted and report the tally.
FOUND=$(grep -coE "sk-or-v1-[A-Za-z0-9_-]{20,}|gho_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[A-Z0-9]{16}" "$FILE" || true)
if [ -n "$FOUND" ] && [ "$FOUND" -ne 0 ]; then
  echo "  ✗ WARN: $FILE still has $FOUND unredacted secret(s)" >&2
  exit 3
fi
echo "  ✓ sanitized $FILE" >&2
exit 0
