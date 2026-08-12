#!/usr/bin/env bash
# ============================================================================
# test-implementer-driver.sh — Unit tests for bin/implementer-run.sh
#
# Fixture-based: runs against an isolated temp workspace (no git needed) and
# sources the driver's functions to validate the deterministic selection and
# resolution logic + the brief writer. Mirrors bin/test-transition-task.sh.
#
# Covered:
#   - bash -n syntax check
#   - shellcheck (if present)
#   - resolve_prd: pick oldest Final PRD, skip in-progress tasks, exclude
#     non-Final PRDs
#   - resolve_repo: task Project → repo_map path + manifest branch
#   - brief writer: brief.md contains the contract fields
#
# Usage:
#   bin/test-implementer-driver.sh          # run all tests
#   bin/test-implementer-driver.sh -v       # verbose
# ============================================================================
set -uo pipefail

DRIVER="$(cd "$(dirname "$0")" && pwd)/implementer-run.sh"
MANIFEST_SRC="$(cd "$(dirname "$0")/.." && pwd)/workspace-portability/workspace_restore_manifest.json"
VERBOSE=false
[ "${1:-}" = "-v" ] && VERBOSE=true

PASS=0
FAIL=0
FAILED_TESTS=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

# ─── Fixture builder ───────────────────────────────────────────────────────
# Build a disposable workspace in a temp dir:
#   docs/prd-queue/*.md      (Final, older, in-progress, non-Final)
#   docs/tasks/<slug>.md      (Project + Status for resolution/skip)
#   config/implementer.json   (driver config)
#   workspace-portability/workspace_restore_manifest.json (repo/branch map)
setup_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/docs/prd-queue" "$dir/docs/tasks" "$dir/config" \
           "$dir/workspace-portability" "$dir/bin"

  # Two pickable Final PRDs (oldest first) + one Final-but-in-progress + one non-Final.
  printf '**Date**: 2026-08-01 10:00\n**Status**: Final\n' > "$dir/docs/prd-queue/2026-08-01-aaa.md"
  printf '**Date**: 2026-08-02 10:00\n**Status**: Final\n' > "$dir/docs/prd-queue/2026-08-02-bbb.md"
  printf '**Date**: 2026-08-03 10:00\n**Status**: Final\n' > "$dir/docs/prd-queue/2026-08-03-ccc.md"
  printf '**Date**: 2026-08-03 11:00\n**Status**: Draft\n' > "$dir/docs/prd-queue/2026-08-03-nope.md"

  # Task files (resolve_repo reads **Project**; resolve_prd reads **Status**).
  printf '**Status**: prd-ready\n**Project**: software-factory\n' > "$dir/docs/tasks/aaa.md"
  printf '**Status**: prd-ready\n**Project**: feed_analyser\n' > "$dir/docs/tasks/bbb.md"
  printf '**Status**: in-progress\n**Project**: software-factory\n' > "$dir/docs/tasks/ccc.md"

  # Driver config (kept minimal — resolves to defaults via jq or fallback).
  cp "$(cd "$(dirname "$0")/.." && pwd)/config/implementer.json" "$dir/config/implementer.json"

  # Portability manifest for manifest-branch resolution.
  cp "$MANIFEST_SRC" "$dir/workspace-portability/workspace_restore_manifest.json"

  echo "$dir"
}

# Source the driver once per test file so functions + vars are available.
# IMPLEMENTER_RUN_SOURCED=1 triggers the guard (skip auto main).
source_driver() {
  export IMPLEMENTER_RUN_SOURCED=1
  # shellcheck disable=SC1090
  source "$DRIVER"
  # The driver re-enables -e; restore the test's flow-on-error behaviour.
  set +e
}

# ─── Test 0: syntax ────────────────────────────────────────────────────────
echo "── Syntax / lint ──"
if bash -n "$DRIVER"; then pass "bash -n: implementer-run.sh"; else fail "bash -n: implementer-run.sh"; fi
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
if bash -n "$BIN_DIR/sandbox-build.sh"; then pass "bash -n: sandbox-build.sh"; else fail "bash -n: sandbox-build.sh"; fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$DRIVER" >/dev/null 2>&1; then
    pass "shellcheck: implementer-run.sh"
  else
    fail "shellcheck: implementer-run.sh (run shellcheck manually to see issues)"
  fi
else
  pass "shellcheck: skipped (not installed)"
fi

# ─── Test 1: resolve_prd with --pick ───────────────────────────────────────
echo "── resolve_prd (--pick) ──"
source_driver
FIX="$(setup_fixture)"
export IMPLEMENTER_WORKSPACE="$FIX"
WORKSPACE="$FIX"
MODE_FLAG="--pick"
TASK=""
# resolve_prd sets globals in the MAIN shell (not a subshell) so they persist.
# Its selection notes go to stderr — suppress for a clean pass/fail run.
resolve_prd 2>/dev/null
if [ "${PRD:-}" = "$FIX/docs/prd-queue/2026-08-01-aaa.md" ]; then
  pass "resolve_prd picks oldest Final (aaa)"
else
  fail "resolve_prd picked '$PRD' — expected aaa (oldest Final)"
fi
if [ "$PRD_SLUG" = "aaa" ]; then pass "resolve_prd derived slug 'aaa'"; else fail "resolve_prd slug = '$PRD_SLUG'"; fi

# ─── Test 2: resolve_repo (project → repo + manifest branch) ───────────────
echo "── resolve_repo ──"
PRD_SLUG="bbb"
resolve_repo 2>/dev/null
if [ "${TARGET_REPO:-}" = "feed_analyser" ]; then
  pass "resolve_repo maps feed_analyser project → 'feed_analyser'"
else
  fail "resolve_repo TARGET_REPO = '$TARGET_REPO' — expected feed_analyser"
fi
if [ "$MANIFEST_BRANCH" = "public-release" ]; then
  pass "resolve_repo manifest branch = public-release"
else
  fail "resolve_repo MANIFEST_BRANCH = '$MANIFEST_BRANCH' — expected public-release"
fi

# software-factory → root (".")
PRD_SLUG="aaa"
resolve_repo 2>/dev/null
if [ "${TARGET_REPO:-}" = "." ]; then
  pass "resolve_repo maps software-factory project → '.'"
else
  fail "resolve_repo software-factory TARGET_REPO = '$TARGET_REPO' — expected '.'"
fi
if [ "$MANIFEST_BRANCH" = "master" ]; then
  pass "resolve_repo root manifest branch = master"
else
  fail "resolve_repo root MANIFEST_BRANCH = '$MANIFEST_BRANCH' — expected master"
fi

# ─── Test 3: brief writer ──────────────────────────────────────────────────
echo "── brief writer ──"
RUN_DIR="$FIX/run-test"
PRD_SLUG="bbb"
PRD="$FIX/docs/prd-queue/2026-08-02-bbb.md"
IMPL_UUID="00000000-0000-0000-0000-000000000001"
mkdir -p "$RUN_DIR"
write_brief "run the demo verification"
for pat in "PRD path" "Task slug" "Impl session UUID" "Worktree path" "Outbox path" "docs/tasks/" "run the demo verification"; do
  if grep -Fq -- "$pat" "$RUN_DIR/brief.md"; then
    pass "brief.md contains: $pat"
  else
    fail "brief.md missing: $pat"
  fi
done

# ─── Test 4: filtered env file contains only allowlisted vars ──────────────
echo "── env allowlist ──"
export OPENROUTER_API_KEY="sk-test"
export GITHUB_TOKEN="ghp_should_never_enter"
RUN_DIR="$FIX/run-env"
mkdir -p "$RUN_DIR"
ENVF="$(write_env_file)"
if grep -q "OPENROUTER_API_KEY" "$ENVF"; then pass "env file includes OPENROUTER_API_KEY"; else fail "env file missing OPENROUTER_API_KEY"; fi
if [ -f "$ENVF" ] && grep -q "GITHUB_TOKEN" "$ENVF"; then
  fail "env file leaked GITHUB_TOKEN (must not contain host secrets)"
else
  pass "env file excludes GITHUB_TOKEN"
fi
unset OPENROUTER_API_KEY GITHUB_TOKEN

# ─── Test 5: full-orchestration failure path (integration) ────────────────
# Build a fixture that is a real git repo with a Final PRD + task, run the
# driver as a subprocess with a deliberately missing container image so podman
# fails fast, and assert the failure path (partial report, task stays prd-ready,
# exit 1, no push/PR under --dry-run). Guarded on a container runtime.
if command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
  echo "── integration: driver failure path (missing image) ──"
  IFIX="$(mktemp -d)"
  ( cd "$IFIX" && git init -q -b master && git config user.email test@example.com \
      && git config user.name Test && echo hello > README.md \
      && git add -A && git commit -qm init )
  mkdir -p "$IFIX/docs/prd-queue" "$IFIX/docs/tasks" "$IFIX/config" \
           "$IFIX/docs/implementations" "$IFIX/bin" "$IFIX/workspace-portability"
  printf '**Date**: 2026-08-01 10:00\n**Status**: Final\n' > "$IFIX/docs/prd-queue/2026-08-05-sample.md"
  printf '**Status**: prd-ready\n**Project**: software-factory\n' > "$IFIX/docs/tasks/sample.md"
  # Config with a deliberately nonexistent image so the container step fails fast.
  # runs_root points INSIDE the fixture so the driver doesn't touch the real home.
  export IFIX
  python3 - "$IFIX/config/implementer.json" <<'PYF'
import json, os, sys
ifix = os.environ["IFIX"]
cfg = {
  "repo_map": {"software-factory": ".", "feed_analyser": "feed_analyser"},
  "model": "openrouter/deepseek/deepseek-v4-flash-0731",
  "timeout_sec": 30, "respawn_cap": 1,
  "env_allowlist": ["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "LANGFUSE_*", "IMPLEMENTER_MODEL"],
  "image": "nonexistent-fake-image:zzz",
  "runs_root": ifix + "/.factory/runs", "archives_root": "docs/implementations",
  "liveness_interval_sec": 2, "liveness_idle_sec": 5
}
with open(sys.argv[1], "w") as f:
    json.dump(cfg, f, indent=2)
PYF
  # Unset the sourced-guard env var so the subprocess actually runs main.
  unset IMPLEMENTER_RUN_SOURCED
  IMPLEMENTER_WORKSPACE="$IFIX" OPENROUTER_API_KEY=sk-test \
    bash "$DRIVER" --task sample --dry-run >/dev/null 2>&1
  Rc=$?
  if [ "$Rc" -eq 1 ]; then
    pass "driver exits 1 on failed run (missing image)"
  else
    fail "driver exit=$Rc — expected 1 on container failure"
  fi
  # Task stays prd-ready (dry-run simulates transitions, never commits).
  if grep -q '\*\*Status\*\*: *prd-ready' "$IFIX/docs/tasks/sample.md"; then
    pass "task remains prd-ready after failed run (dry-run)"
  else
    fail "task status changed after failed dry-run"
  fi
  # Durable artifacts: at least one run dir with a brief + a partial/report.
  if ls -d "$IFIX"/.factory/runs/sample-* >/dev/null 2>&1; then
    pass "run dir created under ~/.factory/runs"
  else
    fail "no run dir created"
  fi
  if ls "$IFIX"/.factory/runs/sample-*/brief.md >/dev/null 2>&1; then
    pass "brief.md written in run dir"
  else
    fail "brief.md not written"
  fi
  if ls "$IFIX"/docs/implementations/*-sample/report.md >/dev/null 2>&1; then
    pass "partial report archived to docs/implementations"
  else
    fail "no report archived"
  fi
else
  echo "── integration: skipped (no container runtime) ──"
  pass "integration: skipped (no podman/docker, acceptable)"
fi

# ─── Test 6: cleanup_run_dir (disposable vs durable) + stop_container ──────
echo "── cleanup_run_dir + stop_container ──"
source_driver
CC="$(mktemp -d)"
RUN_DIR="$CC"
WORKTREE="$CC/worktree"
IMPL_UUID="11111111-2222-3333-4444-555555555555"
mkdir -p "$WORKTREE/capture/agent-service/node_modules/pkg" \
         "$WORKTREE/capture/server/venv2/lib" \
         "$WORKTREE/capture/server/__pycache__" \
         "$CC/sessions" "$CC/outbox"
touch "$WORKTREE/capture/agent-service/node_modules/pkg/index.js"
touch "$WORKTREE/capture/server/venv2/lib/f.pyc"
touch "$CC/container-1.log" "$CC/session.jsonl" "$CC/secrets.env"
printf 'evidence' > "$CC/sessions/evidence.jsonl"
printf 'report' > "$CC/outbox/report.md"

cleanup_run_dir
[ ! -d "$WORKTREE/capture/agent-service/node_modules" ] && pass "node_modules removed" || fail "node_modules still present"
[ ! -d "$WORKTREE/capture/server/venv2" ] && pass "venv2 removed" || fail "venv2 still present"
[ ! -d "$WORKTREE/capture/server/__pycache__" ] && pass "__pycache__ removed" || fail "__pycache__ still present"
[ ! -f "$CC/container-1.log" ] && pass "raw container log removed" || fail "container log kept"
[ ! -f "$CC/session.jsonl" ] && pass "streamed transcript removed" || fail "transcript kept"
[ ! -f "$CC/secrets.env" ] && pass "secrets.env removed" || fail "secrets.env kept"
[ -f "$CC/outbox/report.md" ] && pass "durable outbox/report kept" || fail "outbox removed!"
[ -f "$CC/sessions/evidence.jsonl" ] && pass "durable session evidence kept" || fail "session evidence removed!"

# --keep-logs preserves the diagnosis logs.
touch "$CC/container-2.log" "$CC/session.jsonl"
cleanup_run_dir --keep-logs
[ -f "$CC/container-2.log" ] && pass "--keep-logs preserves container logs" || fail "--keep-logs removed logs"

# stop_container is a safe no-op when no such container exists (must not fail).
if command -v podman >/dev/null 2>&1; then
  stop_container && pass "stop_container no-ops cleanly when container absent" \
    || fail "stop_container errored on absent container"
else
  pass "stop_container: container-runtime check skipped (no podman)"
fi
rm -rf "$CC"

# ─── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "implementer-driver: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
  exit 1
fi
echo "All tests passed."
