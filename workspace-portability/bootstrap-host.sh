#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MODE="install"
PROFILE="full"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--check] [--dry-run] [--restore-only]

Options:
  --check         Verify required commands only; do not install packages
  --dry-run       Print what would be executed
  --restore-only  Only prepare the minimal restore toolchain
  --help          Show this help

Profiles:
  full (default): restore + setup + startup prerequisites
  restore-only:   just enough to run snapshot/restore/verify
EOF
}

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

have_docker_compose() {
  if have_cmd docker-compose; then
    return 0
  fi
  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

command_available() {
  local cmd="$1"
  case "$cmd" in
    docker-compose) have_docker_compose ;;
    *) have_cmd "$cmd" ;;
  esac
}

require_sudo_prefix() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo ""
  elif have_cmd sudo; then
    echo "sudo"
  else
    echo "This script needs root or sudo to install packages" >&2
    exit 1
  fi
}

collect_commands() {
  REQUIRED_COMMANDS=(git python3 tar rclone)
  if [[ "$PROFILE" == "full" ]]; then
    REQUIRED_COMMANDS+=(uv node npm pnpm docker docker-compose age)
  fi
}

missing_commands() {
  local missing=()
  local cmd
  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command_available "$cmd"; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[@]}"
  fi
}

apt_pkg_exists() {
  apt-cache show "$1" >/dev/null 2>&1
}

install_with_apt() {
  local sudo_prefix="$1"
  local packages=(git curl ca-certificates python3 python3-venv tar gzip zstd rclone jq)
  if [[ "$PROFILE" == "full" ]]; then
    packages+=(nodejs npm age docker.io)
  fi
  run_cmd ${sudo_prefix:+$sudo_prefix} apt-get update
  run_cmd ${sudo_prefix:+$sudo_prefix} apt-get install -y "${packages[@]}"

  if [[ "$PROFILE" == "full" ]]; then
    local compose_pkg=""
    for candidate in docker-compose-v2 docker-compose-plugin docker-compose; do
      if apt_pkg_exists "$candidate"; then
        compose_pkg="$candidate"
        break
      fi
    done
    if [[ -n "$compose_pkg" ]]; then
      run_cmd ${sudo_prefix:+$sudo_prefix} apt-get install -y "$compose_pkg"
    fi
  fi
}

install_with_dnf() {
  local sudo_prefix="$1"
  local packages=(git curl ca-certificates python3 python3-pip tar gzip zstd rclone jq)
  if [[ "$PROFILE" == "full" ]]; then
    packages+=(nodejs npm age docker docker-compose)
  fi
  run_cmd ${sudo_prefix:+$sudo_prefix} dnf install -y "${packages[@]}"
}

ensure_uv() {
  if command_available uv; then
    return 0
  fi
  echo "Installing uv..."
  run_cmd bash -lc "curl -LsSf https://astral.sh/uv/install.sh | sh"
}

ensure_pnpm() {
  if command_available pnpm; then
    return 0
  fi
  if have_cmd corepack; then
    run_cmd corepack enable
    run_cmd corepack prepare pnpm@11.1.3 --activate
    return 0
  fi
  if have_cmd npm; then
    local sudo_prefix="$(require_sudo_prefix)"
    run_cmd ${sudo_prefix:+$sudo_prefix} npm install -g pnpm
    return 0
  fi
  echo "Unable to install pnpm automatically (npm/corepack missing)" >&2
  return 1
}

ensure_docker_compose_wrapper() {
  if have_cmd docker-compose; then
    return 0
  fi
  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    local wrapper_dir="$HOME/.local/bin"
    run_cmd mkdir -p "$wrapper_dir"
    if [[ "$DRY_RUN" == true ]]; then
      echo "[dry-run] write $wrapper_dir/docker-compose wrapper"
    else
      cat > "$wrapper_dir/docker-compose" <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
      chmod +x "$wrapper_dir/docker-compose"
    fi
    return 0
  fi
  return 1
}

post_install_fixups() {
  if [[ "$PROFILE" != "full" ]]; then
    return 0
  fi
  ensure_uv
  ensure_pnpm
  ensure_docker_compose_wrapper || true
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        MODE="check"
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --restore-only)
        PROFILE="restore-only"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  collect_commands

  if [[ "$MODE" == "check" ]]; then
    mapfile -t missing < <(missing_commands)
    if [[ ${#missing[@]} -eq 0 ]]; then
      echo "All required commands are available: ${REQUIRED_COMMANDS[*]}"
      exit 0
    fi
    echo "Missing commands: ${missing[*]}" >&2
    exit 1
  fi

  sudo_prefix="$(require_sudo_prefix)"

  if have_cmd apt-get; then
    install_with_apt "$sudo_prefix"
  elif have_cmd dnf; then
    install_with_dnf "$sudo_prefix"
  else
    echo "Unsupported package manager. Install these commands manually: ${REQUIRED_COMMANDS[*]}" >&2
    exit 1
  fi

  post_install_fixups

  mapfile -t missing < <(missing_commands)
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "Host bootstrap complete for profile '$PROFILE'"
    exit 0
  fi

  echo "Bootstrap finished, but some commands are still missing: ${missing[*]}" >&2
  exit 1
}

main "$@"
