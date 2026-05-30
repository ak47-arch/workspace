#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
exec "$WORKSPACE_ROOT/workspace-portability/create_workspace_critical_snapshot.sh" "$@"
