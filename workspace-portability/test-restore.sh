#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=""
RUN_SETUP=true
RUN_START=false
SECRETS_DIR=""
AGE_IDENTITY_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [DEST] [--skip-setup] [--start] [--secrets-dir PATH] [--age-identity-file PATH]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-setup)
      RUN_SETUP=false
      shift
      ;;
    --start)
      RUN_START=true
      shift
      ;;
    --secrets-dir)
      SECRETS_DIR="$2"
      shift 2
      ;;
    --age-identity-file)
      AGE_IDENTITY_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$DEST" ]]; then
        DEST="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DEST" ]]; then
  DEST="$(mktemp -d /tmp/workspace-restore-drill.XXXXXX)"
fi

latest_local_artifact() {
  local snapshot_key="$1"
  python3 - <<PY
import json
from pathlib import Path
manifest = json.loads(Path('$SCRIPT_DIR/workspace_restore_manifest.json').read_text())
cfg = manifest['$snapshot_key']
base = Path(cfg['target_dir'])
exts = tuple(cfg.get('extensions', ['.tar.gz']))
artifacts = sorted(
    p for p in base.glob(f"{cfg['artifact_prefix']}*")
    if any(str(p).endswith(ext) for ext in exts)
)
print(artifacts[-1] if artifacts else '')
PY
}

critical_artifact="$(latest_local_artifact snapshot)"
large_assets_artifact="$(latest_local_artifact large_assets_snapshot)"

if [[ -z "$critical_artifact" ]]; then
  echo "No local critical snapshot artifact found" >&2
  exit 1
fi

args=("$DEST" --local-critical-artifact "$critical_artifact")
if [[ "$RUN_SETUP" == false ]]; then
  args+=(--skip-setup)
fi
if [[ "$RUN_START" == true ]]; then
  args+=(--start)
fi
if [[ -n "$large_assets_artifact" ]]; then
  args+=(--local-large-assets-artifact "$large_assets_artifact")
else
  args+=(--skip-assets)
fi
if [[ -n "$SECRETS_DIR" ]]; then
  args+=(--secrets-dir "$SECRETS_DIR")
fi
if [[ -n "$AGE_IDENTITY_FILE" ]]; then
  args+=(--age-identity-file "$AGE_IDENTITY_FILE")
fi

"$SCRIPT_DIR/full-restore.sh" "${args[@]}"

echo "Restore drill complete: $DEST"
