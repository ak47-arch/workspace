#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=""
BOOTSTRAP_MODE="check"
RUN_SETUP=true
RUN_ASSET_HYDRATION=true
RUN_START=false
SECRETS_DIR=""
AGE_IDENTITY_FILE=""
CRITICAL_ARTIFACT=""
LARGE_ASSETS_ARTIFACT=""
START_TARGETS=()

usage() {
  cat <<EOF
Usage: $(basename "$0") DEST [options]

Options:
  --bootstrap                       Run bootstrap-host.sh install mode
  --skip-setup                      Skip setup-workspace.sh
  --skip-assets                     Skip hydrate-large-assets.sh
  --start                           Start default runtime targets after restore
  --target NAME                     Start a specific runtime target (repeatable)
  --secrets-dir PATH                Materialize file secrets from this directory if needed
  --age-identity-file PATH          Identity file for encrypted snapshot artifacts
  --local-critical-artifact PATH    Restore critical snapshot from a local artifact
  --local-large-assets-artifact PATH Restore large assets from a local artifact
  --help                            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap)
      BOOTSTRAP_MODE="install"
      shift
      ;;
    --skip-setup)
      RUN_SETUP=false
      shift
      ;;
    --skip-assets)
      RUN_ASSET_HYDRATION=false
      shift
      ;;
    --start)
      RUN_START=true
      shift
      ;;
    --target)
      RUN_START=true
      START_TARGETS+=("$2")
      shift 2
      ;;
    --secrets-dir)
      SECRETS_DIR="$2"
      shift 2
      ;;
    --age-identity-file)
      AGE_IDENTITY_FILE="$2"
      shift 2
      ;;
    --local-critical-artifact)
      CRITICAL_ARTIFACT="$2"
      shift 2
      ;;
    --local-large-assets-artifact)
      LARGE_ASSETS_ARTIFACT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$DEST" ]]; then
        DEST="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DEST" ]]; then
  usage >&2
  exit 1
fi

if [[ "$BOOTSTRAP_MODE" == "install" ]]; then
  "$SCRIPT_DIR/bootstrap-host.sh"
else
  "$SCRIPT_DIR/bootstrap-host.sh" --check
fi

restore_args=("$DEST")
if [[ -n "$AGE_IDENTITY_FILE" ]]; then
  restore_args+=(--age-identity-file "$AGE_IDENTITY_FILE")
fi
if [[ -n "$CRITICAL_ARTIFACT" ]]; then
  restore_args+=(--skip-download --local-artifact "$CRITICAL_ARTIFACT")
fi
"$SCRIPT_DIR/restore-workspace.sh" "${restore_args[@]}"

secret_args=("$DEST")
if [[ -n "$SECRETS_DIR" ]]; then
  secret_args+=(--secrets-dir "$SECRETS_DIR")
fi
"$SCRIPT_DIR/materialize-secrets.sh" "${secret_args[@]}"

if [[ "$RUN_ASSET_HYDRATION" == true ]]; then
  asset_args=("$DEST")
  if [[ -n "$AGE_IDENTITY_FILE" ]]; then
    asset_args+=(--age-identity-file "$AGE_IDENTITY_FILE")
  fi
  if [[ -n "$LARGE_ASSETS_ARTIFACT" ]]; then
    asset_args+=(--skip-download --local-artifact "$LARGE_ASSETS_ARTIFACT")
  fi
  "$SCRIPT_DIR/hydrate-large-assets.sh" "${asset_args[@]}"
fi

if [[ "$RUN_SETUP" == true ]]; then
  "$SCRIPT_DIR/setup-workspace.sh" "$DEST"
fi

if [[ "$RUN_START" == true ]]; then
  startup_secret_args=("$DEST" --startup-phase)
  if [[ -n "$SECRETS_DIR" ]]; then
    startup_secret_args+=(--secrets-dir "$SECRETS_DIR")
  fi
  "$SCRIPT_DIR/materialize-secrets.sh" "${startup_secret_args[@]}"
  start_args=("$DEST")
  for target in "${START_TARGETS[@]}"; do
    start_args+=(--target "$target")
  done
  "$SCRIPT_DIR/start-services.sh" "${start_args[@]}"
  verify_args=("$DEST" --services)
  for target in "${START_TARGETS[@]}"; do
    verify_args+=("$target")
  done
  "$SCRIPT_DIR/verify-workspace.sh" "${verify_args[@]}"
else
  "$SCRIPT_DIR/verify-workspace.sh" "$DEST"
fi

echo "Full restore complete: $DEST"
