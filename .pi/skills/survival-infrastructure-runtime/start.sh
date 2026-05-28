#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SKILL_DIR/../../.." && pwd)"
exec "$WORKSPACE_DIR/survival-infrastructure/start_stack.sh" "$@"
