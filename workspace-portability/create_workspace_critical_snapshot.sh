#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_SCRIPT="$WORKSPACE_ROOT/backup-tool/backup.sh"
TARGET_DIR="/home/anupam/Desktop/backup_data/workspace-critical-snapshot"
JOB_NAME="workspace_critical_snapshot"
UPLOAD_TO_DRIVE="${UPLOAD_TO_DRIVE:-true}"
RCLONE_REMOTE="${RCLONE_REMOTE:-workspace:workspace-critical-snapshot}"
REMOTE_RETENTION_COUNT="${REMOTE_RETENTION_COUNT:-5}"
TEMP_ROOT="$(mktemp -d /tmp/workspace-critical-snapshot.XXXXXX)"
STAGE_DIR="$TEMP_ROOT/workspace-critical-snapshot"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/snapshot_common.sh"

INCLUDE_PATHS=(
  "survival-infrastructure/data"
  "survival-infrastructure/data-prod"
  "survival-infrastructure/data_prod_copy"
  "survival-infrastructure/.runtime-data"
  "survival-infrastructure/.env"
  "feed_analyser/backend/data.db"
  "feed_analyser/backend/raw_data"
  "feed_analyser/backend/archive"
  "hermes/.hermes-data"
)

HERMES_EXCLUDES=(
  ".hermes-data/.cache"
  ".hermes-data/.npm"
  ".hermes-data/audio_cache"
  ".hermes-data/image_cache"
  ".hermes-data/logs"
  ".hermes-data/cache"
  ".hermes-data/ollama_cloud_models_cache.json"
  ".hermes-data/models_dev_cache.json"
  ".hermes-data/.update_check"
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

  if [[ "$rel_path" == "hermes/.hermes-data" ]]; then
    local tar_excludes=()
    local pattern
    for pattern in "${HERMES_EXCLUDES[@]}"; do
      tar_excludes+=("--exclude=$pattern")
    done
    tar -C "$WORKSPACE_ROOT/hermes" "${tar_excludes[@]}" -cf - .hermes-data | tar -C "$dest_parent" -xf -
  else
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
Workspace critical snapshot
Generated: $(date --iso-8601=seconds)
Source root: $WORKSPACE_ROOT

Included paths:
$(printf '%s\n' "${INCLUDE_PATHS[@]}")

Hermes exclusions:
$(printf '%s\n' "${HERMES_EXCLUDES[@]}")
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

echo "Latest local snapshot: $artifact"
if [[ "$artifact_to_upload" != "$artifact" ]]; then
  echo "Encrypted upload artifact: $artifact_to_upload"
fi

if [[ "$UPLOAD_TO_DRIVE" == "true" ]]; then
  upload_artifact_and_checksum "$RCLONE_REMOTE" "$artifact_to_upload"
  prune_remote_artifacts "$RCLONE_REMOTE" "${JOB_NAME}_" "$REMOTE_RETENTION_COUNT"
  echo "Uploaded to: $RCLONE_REMOTE"
fi
