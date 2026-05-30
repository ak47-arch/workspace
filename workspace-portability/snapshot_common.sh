#!/usr/bin/env bash
set -euo pipefail

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

create_sha256() {
  local artifact="$1"
  sha256sum "$artifact" > "${artifact}.sha256"
}

encrypt_artifact_if_requested() {
  local artifact="$1"
  local mode="${SNAPSHOT_ENCRYPTION:-none}"

  if [[ "$mode" == "none" ]]; then
    create_sha256 "$artifact"
    echo "$artifact"
    return 0
  fi

  if [[ "$mode" != "age" ]]; then
    echo "Unsupported SNAPSHOT_ENCRYPTION mode: $mode" >&2
    exit 1
  fi

  require_command age
  local encrypted="${artifact}.age"
  local -a args=()

  if [[ -n "${AGE_RECIPIENTS_FILE:-}" ]]; then
    while IFS= read -r recipient; do
      [[ -z "$recipient" ]] && continue
      args+=("-r" "$recipient")
    done < "$AGE_RECIPIENTS_FILE"
  elif [[ -n "${AGE_RECIPIENT:-}" ]]; then
    IFS=',' read -r -a recipients <<< "$AGE_RECIPIENT"
    local recipient
    for recipient in "${recipients[@]}"; do
      [[ -z "$recipient" ]] && continue
      args+=("-r" "$recipient")
    done
  else
    echo "SNAPSHOT_ENCRYPTION=age requires AGE_RECIPIENT or AGE_RECIPIENTS_FILE" >&2
    exit 1
  fi

  age "${args[@]}" -o "$encrypted" "$artifact"
  create_sha256 "$encrypted"
  echo "$encrypted"
}

upload_artifact_and_checksum() {
  local remote="$1"
  local artifact="$2"
  local checksum="${artifact}.sha256"

  if [[ ! -f "$artifact" ]]; then
    echo "Artifact not found for upload: $artifact" >&2
    exit 1
  fi

  if [[ ! -f "$checksum" ]]; then
    echo "Checksum not found for upload: $checksum" >&2
    exit 1
  fi

  echo "Uploading snapshot to $remote"
  rclone copyto "$artifact" "$remote/$(basename "$artifact")"
  rclone copyto "$checksum" "$remote/$(basename "$checksum")"
}

prune_remote_artifacts() {
  local remote="$1"
  local prefix="$2"
  local retention_count="$3"

  local artifacts
  artifacts="$(rclone lsf --files-only "$remote" 2>/dev/null | grep -E "^${prefix}[0-9]{8}_[0-9]{6}\.tar\.gz(\.age)?$" | sort || true)"

  [[ -z "$artifacts" ]] && return 0

  mapfile -t artifact_list <<< "$artifacts"
  local total_count="${#artifact_list[@]}"
  if [[ "$total_count" -le "$retention_count" ]]; then
    return 0
  fi

  local to_delete=$((total_count - retention_count))
  local i
  for ((i=0; i<to_delete; i++)); do
    local name="${artifact_list[$i]}"
    echo "Pruning remote artifact: $name"
    rclone deletefile "$remote/$name" || true
    rclone deletefile "$remote/${name}.sha256" || true
  done
}
