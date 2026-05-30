#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_SCRIPT="$WORKSPACE_ROOT/backup-tool/backup.sh"
TARGET_DIR="/home/anupam/Desktop/backup_data/workspace-large-assets"
JOB_NAME="workspace_large_assets"
UPLOAD_TO_DRIVE="${UPLOAD_TO_DRIVE:-true}"
RCLONE_REMOTE="${RCLONE_REMOTE:-workspace:workspace-large-assets}"
REMOTE_RETENTION_COUNT="${REMOTE_RETENTION_COUNT:-2}"
TEMP_ROOT="$(mktemp -d "$WORKSPACE_ROOT/.workspace-large-assets.XXXXXX")"
STAGE_DIR="$TEMP_ROOT/workspace-large-assets"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/snapshot_common.sh"

INCLUDE_PATHS=(
  "llm/gemma"
)

cleanup() {
  rm -rf "$TEMP_ROOT"
}

trap cleanup EXIT

validate_environment() {
  require_command tar
  require_command cp
  require_command sha256sum

  if [[ ! -x "$BACKUP_SCRIPT" ]]; then
    echo "Backup script not executable: $BACKUP_SCRIPT" >&2
    exit 1
  fi

  if [[ "$UPLOAD_TO_DRIVE" == "true" ]]; then
    require_command rclone
  fi
}

copy_path() {
  local rel_path="$1"
  local src="$WORKSPACE_ROOT/$rel_path"
  local dest_parent="$STAGE_DIR/$(dirname "$rel_path")"

  if [[ ! -e "$src" ]]; then
    echo "Missing required path: $src" >&2
    exit 1
  fi

  mkdir -p "$dest_parent"
  if ! cp -al "$src" "$dest_parent/" 2>/dev/null; then
    cp -a "$src" "$dest_parent/"
  fi
}

find_latest_artifact() {
  find "$TARGET_DIR" -maxdepth 1 -type f -name "${JOB_NAME}_*.tar.gz" | sort | tail -1
}

validate_environment
mkdir -p "$STAGE_DIR"

for rel_path in "${INCLUDE_PATHS[@]}"; do
  copy_path "$rel_path"
done

cat > "$STAGE_DIR/INCLUDED_PATHS.txt" <<EOF
Workspace large assets snapshot
Generated: $(date --iso-8601=seconds)
Source root: $WORKSPACE_ROOT

Included paths:
$(printf '%s\n' "${INCLUDE_PATHS[@]}")
EOF

mkdir -p "$TARGET_DIR"

"$BACKUP_SCRIPT" \
  --source "$STAGE_DIR" \
  --target "$TARGET_DIR" \
  --job-name "$JOB_NAME" \
  --retention 1 \
  "$@"

if printf '%s\n' "$@" | grep -qx -- '--dry-run'; then
  echo "Dry-run requested; skipping upload and encryption"
  exit 0
fi

artifact="$(find_latest_artifact)"
if [[ -z "$artifact" ]]; then
  echo "Unable to locate created snapshot artifact in $TARGET_DIR" >&2
  exit 1
fi

artifact_to_upload="$(encrypt_artifact_if_requested "$artifact")"

echo "Latest local large-asset snapshot: $artifact"
if [[ "$artifact_to_upload" != "$artifact" ]]; then
  echo "Encrypted upload artifact: $artifact_to_upload"
fi

if [[ "$UPLOAD_TO_DRIVE" == "true" ]]; then
  upload_artifact_and_checksum "$RCLONE_REMOTE" "$artifact_to_upload"
  prune_remote_artifacts "$RCLONE_REMOTE" "${JOB_NAME}_" "$REMOTE_RETENTION_COUNT"
  echo "Uploaded to: $RCLONE_REMOTE"
fi
