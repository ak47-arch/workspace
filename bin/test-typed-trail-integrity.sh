#!/usr/bin/env bash
# ============================================================================
# test-typed-trail-integrity.sh — falsifiability proof for the S10 typed-trail
# hygiene checks (typed-trail-integrity PRD).
#
# The register's anti-fabrication rule demands every check be flippable: a row
# that cannot be made to FAIL is dead weight. This suite builds a minimal
# fixture workspace and proves each S10 check:
#   (a) string-path refs  — inject a backticked string path → FAIL
#   (b) Summary present   — remove a `**Summary**:` line → FAIL
#   (c) stale/mismatch    — inject a prd-queue/ citation / break manifest → FAIL
# It also asserts the clean fixture PASSes every check (no can't-fail rows).
# ============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/test-typed-trail-integrity.py"

if [ ! -f "$PY" ]; then
  echo "FATAL: missing $PY" >&2
  exit 1
fi

python3 "$PY"