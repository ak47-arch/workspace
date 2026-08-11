#!/usr/bin/env bash
# ============================================================================
# sandbox-build.sh — Build the implementer sandbox container image.
#
# Builds the OCI image the implementer runs inside (the "hands"). The image is
# defined by workspace-portability/container/Dockerfile and contains pi (npm
# global), node, git, python, the portability tooling, and a scoped pi config
# (defaultProjectTrust=always). Secrets are NEVER baked into the image; repo
# clones happen at run time only on cloud workers.
#
# Usage:
#   bin/sandbox-build.sh [--tag <name:tag>]
#
# Default tag: sandbox:<commit-short> (or sandbox:latest if no git).
# The config's "image" value ("sandbox:latest") is what implementer-run.sh
# uses by default; pass --tag to override and then set config/implementer.json
# "image" accordingly.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_DIR="$SCRIPT_DIR/workspace-portability/container"

TAG="${IMPLEMENTER_IMAGE_TAG:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TAG" ]; then
  SHORT="$(cd "$SCRIPT_DIR/workspace-portability" && git rev-parse --short HEAD 2>/dev/null || echo latest)"
  TAG="sandbox:$SHORT"
fi

if [ ! -d "$CONTAINER_DIR" ]; then
  echo "ERROR: container context not found: $CONTAINER_DIR" >&2
  echo "  Ensure workspace-portability/container/{Dockerfile,entrypoint} exists." >&2
  exit 1
fi

command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 \
  || { echo "ERROR: no container runtime (podman/docker) found." >&2; exit 1; }

echo "=== building implementer sandbox image ==="
echo "  tag:     $TAG"
echo "  context: $CONTAINER_DIR"
podman build -t "$TAG" "$CONTAINER_DIR"
echo "=== done: $TAG ==="
