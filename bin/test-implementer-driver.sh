
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
  # STALE case (decision 09): a Final PRD whose task is in-review (merged/blocked
  # lineage) — must NOT be picked even though it is the OLDEST Final.
  printf '**Date**: 2026-07-31 10:00\n**Status**: Final\n' > "$dir/docs/prd-queue/2026-07-31-ddd.md"

  # Task files (resolve_repo reads **Project**; resolve_prd reads **Status**).
  printf '**Status**: prd-ready\n**Project**: software-factory\n' > "$dir/docs/tasks/aaa.md"
  printf '**Status**: prd-ready\n**Project**: feed_analyser\n' > "$dir/docs/tasks/bbb.md"
  printf '**Status**: in-progress\n**Project**: software-factory\n' > "$dir/docs/tasks/ccc.md"
  printf '**Status**: in-review\n**Project**: software-factory\n' > "$dir/docs/tasks/ddd.md"

  # Driver config (kept minimal — resolves to defaults via jq or fallback).
  cp "$(cd "$(dirname "$0")/.." && pwd)/config/implementer.json" "$dir/config/implementer.json"

  # Portability manifest for manifest-branch resolution. Fall back to a
  # self-contained fixture manifest when the sibling workspace-portability repo
  # isn't checked out (it lives in a separate repo of the factory workspace, so
  # a standalone software-factory checkout may not carry it).
  if [ -f "$MANIFEST_SRC" ]; then
    cp "$MANIFEST_SRC" "$dir/workspace-portability/workspace_restore_manifest.json"
  else
    cat > "$dir/workspace-portability/workspace_restore_manifest.json" <<'MF'
{
  "repos": [
    { "path": ".", "branch": "master" },
    { "path": "feed_analyser", "branch": "public-release" }
  ]
}
MF
  fi

  echo "$dir"
}

# ─── make_mock_podman(): fabricate completion so the driver's `main` executes
# end-to-end. Records its args to a log, and for `podman run` parses the
# `-v <host>:/sandbox` mount to write a fabricated report into the run-dir
# outbox — which is exactly the driver's success signal.
make_mock_podman() {
  cat > "$1" <<'MOCK'
#!/usr/bin/env bash
LOG="$MOCK_PODMAN_LOG"
{
  printf 'podman'
  for a in "$@"; do printf ' <%s>' "$a"; done
  printf '\n'
} >> "$LOG"
# Locate the /sandbox host dir from the -v mount args (the run dir).
sandbox=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-v" ]; then
    case "$a" in
      *:/sandbox) sandbox="${a%%:/sandbox}" ;;
    esac
  fi
  prev="$a"
done
if [ "${1:-}" = "run" ]; then
  mkdir -p "$sandbox/outbox/decisions"
  cat > "$sandbox/outbox/report.md" <<'RPT'
# Implementer (fixture smoke)
## Summary
All stories implemented — fabricated by mock podman for the end-to-end driver smoke.
RPT
fi
exit 0
MOCK
  chmod +x "$1"
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
# Capture its stderr notes via a file — a $( ) substitution would run it in a
# subshell and lose the globals.
resolve_prd 2> "$FIX/pick-notes.txt"
NOTES="$(cat "$FIX/pick-notes.txt")"
if [ "${PRD:-}" = "$FIX/docs/prd-queue/2026-08-01-aaa.md" ]; then
  pass "resolve_prd picks oldest Final prd-ready (aaa)"
else
  fail "resolve_prd picked '$PRD' — expected aaa (oldest Final prd-ready)"
fi
if [ "$PRD_SLUG" = "aaa" ]; then pass "resolve_prd derived slug 'aaa'"; else fail "resolve_prd slug = '$PRD_SLUG'"; fi
# Decision 09: stale lineages must be skipped — ddd (in-review, OLDEST Final)
# and ccc (in-progress) are NOT prd-ready.
echo "$NOTES" | grep -q "skipping ddd" \
  && pass "resolve_prd skips in-review task (ddd — merged/blocked lineage)" \
  || fail "resolve_prd did not skip ddd (in-review): $(echo "$NOTES" | tr '\n' ' ')"
echo "$NOTES" | grep -q "skipping ccc" \
  && pass "resolve_prd skips in-progress task (ccc — concurrent owner)" \
  || fail "resolve_prd did not skip ccc (in-progress): $(echo "$NOTES" | tr '\n' ' ')"

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
export PONYTAIL_DEFAULT_MODE="ultra"
RUN_DIR="$FIX/run-env"
mkdir -p "$RUN_DIR"
ENVF="$(write_env_file)"
if grep -q "OPENROUTER_API_KEY" "$ENVF"; then pass "env file includes OPENROUTER_API_KEY"; else fail "env file missing OPENROUTER_API_KEY"; fi
if [ -f "$ENVF" ] && grep -q "PONYTAIL_DEFAULT_MODE=ultra" "$ENVF"; then
  pass "env file forces PONYTAIL_DEFAULT_MODE=ultra"
else
  fail "env file missing PONYTAIL_DEFAULT_MODE=ultra"
fi
if [ -f "$ENVF" ] && grep -q "GITHUB_TOKEN" "$ENVF"; then
  fail "env file leaked GITHUB_TOKEN (must not contain host secrets)"
else
  pass "env file excludes GITHUB_TOKEN"
fi
unset OPENROUTER_API_KEY GITHUB_TOKEN PONYTAIL_DEFAULT_MODE

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

# ─── Test 5b: end-to-end smoke — the driver's `main` is EXECUTED (not just
# sourced) against a mock podman (IMPLEMENTER_PODMAN_BIN) under --dry-run. This
# proves the pi invocation carries all six ponytail --skill flags from the live
# skills dir plus the ultra mode, AND that the env file is token-free. The
# fixture ships bin/sort-knowledge-index.py + a writable docs/knowledge/ because
# the implementer success path shells out to append_decisions_to_index.
# ───────────────────────────────────────────────────────────────────────────
echo "── end-to-end smoke: driver main executed (mock podman, --dry-run) ──"
SMOKE="$(mktemp -d)"
mkdir -p "$SMOKE/config" "$SMOKE/docs/tasks" "$SMOKE/docs/prd-queue" \
         "$SMOKE/docs/implementations" "$SMOKE/docs/knowledge/sessions" "$SMOKE/bin"
# Stub the host skills checkout the driver binds into the container at /skills.
# US2/US3: the mount source must exist so the /skills mount + `--skill /skills/*`
# flags are emitted (US4's warn-and-run path is exercised elsewhere). The stub
# is a test-time scratch dir, never part of the worktree/repo.
mkdir -p "$SMOKE/opensource/ponytail/skills/ponytail-review"/
( cd "$SMOKE" && git init -q -b master >/dev/null 2>&1 \
    && git config user.email smoke@example.com && git config user.name Smoker \
    && echo base > base.txt && git add -A && git commit -qm base >/dev/null 2>&1 )
printf '**Status**: prd-ready\n**Project**: software-factory\n' > "$SMOKE/docs/tasks/pony.md"
printf '**Date**: 2026-08-14 12:00\n**Status**: Final\n## Testing decisions\nrun the demo verification\n' \
  > "$SMOKE/docs/prd-queue/2026-08-14-pony.md"
cat > "$SMOKE/config/implementer.json" <<'CFG'
{
  "repo_map": { "software-factory": ".", "feed_analyser": "feed_analyser" },
  "model": "openrouter/deepseek/deepseek-v4-flash-0731",
  "timeout_sec": 30, "respawn_cap": 1,
  "env_allowlist": ["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "LANGFUSE_*", "IMPLEMENTER_MODEL", "PONYTAIL_DEFAULT_MODE"],
  "image": "sandbox:latest",
  "runs_root": ".factory/runs", "archives_root": "docs/implementations",
  "liveness_interval_sec": 2, "liveness_idle_sec": 5,
  "ponytail": { "skills_dir": "/skills", "host_skills_dir": "$WORKSPACE/opensource/ponytail/skills", "default_mode": "ultra" }
}
CFG
# The success path shells out to append_decisions_to_index → sort-knowledge-index.
cp "$(cd "$(dirname "$0")" && pwd)/sort-knowledge-index.py" "$SMOKE/bin/sort-knowledge-index.py"
# A stub transition-task.sh so any accidental non-dry-run call is a no-op.
printf '#!/usr/bin/env bash\nexit 0\n' > "$SMOKE/bin/transition-task.sh"
chmod +x "$SMOKE/bin/transition-task.sh"

export MOCK_PODMAN_LOG="$SMOKE/podman-calls.log"
make_mock_podman "$SMOKE/mock-podman.sh"
# Real subprocess: bash <driver> --task pony --dry-run, full main, fixture workspace.
# IMPLEMENTER_RUN_SOURCED is reset to 0 — the parent shell sourced the driver
# (exporting 1) and the subprocess would otherwise exit at the source-guard on 0.
(
  cd "$SMOKE"
  # HOME is pinned to the fixture so the driver's jq-less fallback runs root
  # ($HOME/.factory/runs) lands inside the fixture just like the config path.
  HOME="$SMOKE" IMPLEMENTER_RUN_SOURCED=0 IMPLEMENTER_WORKSPACE="$SMOKE" \
  IMPLEMENTER_PODMAN_BIN="$SMOKE/mock-podman.sh" \
  bash "$DRIVER" --task pony --dry-run
) > "$SMOKE/smoke.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "main executes end-to-end under --dry-run (exit 0)"
else
  fail "main crashed under --dry-run (exit $rc): $(tail -3 "$SMOKE/smoke.out" | tr '\n' ' ')"
fi
# All six --skill flags, resolving under the fixed /skills container path. The
# mock log wraps each argv element in angle brackets (`<arg>`), so match the
# skill path (which always carries the `--skill` prefix in the diagnostic line).
flag_ok=1
for sk in ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help; do
  grep -q -- "--skill> </skills/$sk>" "$MOCK_PODMAN_LOG" \
    || flag_ok=0
done
if [ "$flag_ok" -eq 1 ]; then
  pass "smoke: six ponytail --skill flags from the fixed /skills path in the podman invocation"
else
  fail "smoke: ponytail --skill flags missing from podman invocation: $(cat "$MOCK_PODMAN_LOG" | tr '\n' ' ')"
fi
echo "  smoke: flag count = $(grep -o -- '--skill' "$MOCK_PODMAN_LOG" | wc -l)" >&2
# US2: the read-only /skills bind mount appears in the invocation (not path
# inheritance from a host checkout).
if grep -q ':/skills:ro' "$MOCK_PODMAN_LOG"; then
  pass "smoke: read-only /skills bind mount present in the podman invocation"
else
  fail "smoke: /skills:ro mount missing from podman invocation: $(cat "$MOCK_PODMAN_LOG" | tr '\n' ' ')"
fi
# US4: the warn-and-run seam is wired — the driver warns (never fail-fast) when
# the host skills checkout is absent, and still runs.
if grep -q 'ponytail skills not found at' "$DRIVER" && grep -q 'running without ponytail discipline' "$DRIVER"; then
  pass "smoke: US4 warn-and-run branch present in the driver"
else
  fail "smoke: US4 warn-and-run warning line missing from driver"
fi
if grep -q "PONYTAIL_DEFAULT_MODE=ultra" "$SMOKE"/.factory/runs/*/secrets.env 2>/dev/null \
   || grep -q "PONYTAIL_DEFAULT_MODE=ultra" "$MOCK_PODMAN_LOG"; then
  pass "smoke: PONYTAIL_DEFAULT_MODE=ultra carried to the container"
else
  fail "smoke: ultra mode env missing"
fi
if ! grep -q "GITHUB_TOKEN" "$SMOKE"/.factory/runs/*/secrets.env 2>/dev/null; then
  pass "smoke: env file carries no GitHub token"
else
  fail "smoke: GitHub token leaked into env file"
fi
rm -rf "$SMOKE"

# ─── Test 5b: write_env_file resolves LLM credentials from pi's auth.json ──
# The sandbox needs OPENROUTER_API_KEY/ANTHROPIC_API_KEY; pi keeps its key in
# ~/.pi/agent/auth.json (not the host env). The driver must fall back to that
# file, only for allowlisted provider keys — never github-copilot / nvidia.
echo "── write_env_file: auth.json credential fallback ──"
source_driver
AUTH_HOME="$(mktemp -d)"
mkdir -p "$AUTH_HOME/.pi/agent" "$AUTH_HOME/run"
cat > "$AUTH_HOME/.pi/agent/auth.json" <<'AUTHJSON'
{
  "openrouter": { "type": "openrouter", "key": "sk-or-v1-test-openrouter-key" },
  "anthropic": { "type": "anthropic", "key": "sk-ant-test-anthropic-key" },
  "github-copilot": { "type": "github-copilot", "access": "gho_should-never-leak" },
  "nvidia": { "type": "nvidia", "key": "nvapi-should-never-leak" }
}
AUTHJSON

# Case 1: neither env var set → both resolved from auth.json, GH/nvidia excluded.
(
  export HOME="$AUTH_HOME"
  unset OPENROUTER_API_KEY ANTHROPIC_API_KEY
  RUN_DIR="$AUTH_HOME/run"
  ENVF="$(write_env_file)"
  grep -q "^OPENROUTER_API_KEY=sk-or-v1-test-openrouter-key$" "$ENVF" \
    && pass "auth.json: OPENROUTER_API_KEY resolved from pi auth.json" \
    || fail "auth.json: OPENROUTER_API_KEY missing from env file"
  grep -q "^ANTHROPIC_API_KEY=sk-ant-test-anthropic-key$" "$ENVF" \
    && pass "auth.json: ANTHROPIC_API_KEY resolved from pi auth.json" \
    || fail "auth.json: ANTHROPIC_API_KEY missing from env file"
  ! grep -q "gho_\|nvapi" "$ENVF" \
    && pass "auth.json: github-copilot/nvidia keys excluded" \
    || fail "auth.json: GH/nvidia key leaked into env file"
)

# Case 2: host env var set → it wins (explicit override, no auth.json lookup).
(
  export HOME="$AUTH_HOME"
  export OPENROUTER_API_KEY="sk-env-explicit-override"
  unset ANTHROPIC_API_KEY
  RUN_DIR="$AUTH_HOME/run"
  ENVF="$(write_env_file)"
  grep -q "^OPENROUTER_API_KEY=sk-env-explicit-override$" "$ENVF" \
    && pass "auth.json: host env var overrides auth.json" \
    || fail "auth.json: host env override lost"
)

# Case 3: no auth.json → env file simply lacks LLM creds (entrypoint will fail
# clearly), no crash.
(
  export HOME="$AUTH_HOME/empty-home"
  mkdir -p "$AUTH_HOME/empty-home"
  unset OPENROUTER_API_KEY ANTHROPIC_API_KEY
  RUN_DIR="$AUTH_HOME/run"
  ENVF="$(write_env_file)"
  ! grep -q "OPENROUTER_API_KEY\|ANTHROPIC_API_KEY" "$ENVF" \
    && pass "auth.json: absent file → no LLM creds, no crash" \
    || fail "auth.json: expected no LLM creds without auth.json"
)
rm -rf "$AUTH_HOME"

# ─── Test 6: cleanup worktree (disposable vs durable) + stop_container ──────
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

# ─── Revision-mode mocks + fixture (decision 08) ───────────────────────────
# Mock gh: records calls; answers `pr view` with the fixture JSON (state + merged
# + title + refs). `pr create` is legal to CALL but the test asserts it is ABSENT
# from the log (D4 — delivery never raises a new PR).
make_mock_gh_impl() {
  local logfile="$1"
  cat > "$2" <<'MOCK'
#!/usr/bin/env bash
LOG="$MOCK_GH_LOG"
{
  printf 'gh'
  for a in "$@"; do printf ' <%s>' "$a"; done
  printf '\n'
} >> "$LOG"
cmd="$1"; shift
case "$cmd" in
  pr)
    sub="$1"; shift
    case "$sub" in
      view)
        # Harden the seam: reject fields real gh 2.45 does not support
        # (e.g. `merged` — the host bug that hid until --revise 2 on real gh).
        prev=""; for a in "$@"; do
          if [ "$prev" = "--json" ]; then
            for f in ${a//,/ }; do
              case "$f" in
                number|title|headRefName|baseRefName|headRefOid|state) : ;;
                *) printf 'Unknown JSON field: "%s"\n' "$f" >&2; exit 1 ;;
              esac
            done
          fi
          prev="$a"
        done
        printf '%s' "$MOCK_GH_VIEW_JSON" ;;
      comment) printf 'commented\n' ;;
      create) printf 'create-called\n' ;;
      *) printf 'ok\n' ;;
    esac
    ;;
esac
MOCK
  chmod +x "$2"
}

# Mock podman: writes a fabricated revision report into the /sandbox outbox so
# the driver's `main` (revise mode) executes end-to-end and records the args so
# the test can assert the seeded-session `--continue` continuity seam.
make_mock_podman_impl() {
  cat > "$1" <<'MOCK'
#!/usr/bin/env bash
LOG="$MOCK_PODMAN_LOG"
{
  printf 'podman'
  for a in "$@"; do printf ' <%s>' "$a"; done
  printf '\n'
} >> "$LOG"
# Locate the /sandbox host dir from the -v mount args (the run dir).
sandbox=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-v" ]; then
    case "$a" in
      *:/sandbox) sandbox="${a%%:/sandbox}" ;;
    esac
  fi
  prev="$a"
done
if [ "${1:-}" = "run" ]; then
  mkdir -p "$sandbox/outbox/decisions"
  cat > "$sandbox/outbox/report.md" <<'RPT'
# Implementer Revision (fixture smoke)

All review findings addressed. (fabricated by mock podman for the driver smoke)
RPT
  # The real implementer edits the worktree; mirror that so delivery has a
  # change to commit + push on the same branch.
  printf '\nrevision fix (fixture)\n' >> "$sandbox/worktree/base.txt"
fi
exit 0
MOCK
  chmod +x "$1"
}

# Revision fixture: a scratch git repo with a bare `origin` remote carrying both
# master and the PR head branch, a reviewed task file (decision 06 rows), the
# original impl session file, and a REQUEST_CHANGES review report + decisions.
# PRD_SLUG=demo, PR #2, branch factory/demo/20260814-120000.
setup_revise_fixture() {
  local slug="demo"
  local branch="factory/demo/20260814-120000"
  local orig="aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001"
  local rev="11111111-2222-3333-4444-555555555555"
  local date="2026-08-14"
  local dir
  dir="$(mktemp -d)"
  local remote="$dir-remote"
  mkdir -p "$dir/config" "$dir/docs/tasks" "$dir/docs/prd-queue" \
           "$dir/docs/code-reviews/$date-$slug/decisions" \
           "$dir/docs/implementations" "$dir/docs/knowledge/sessions/$orig" \
           "$dir/bin" "$dir/.factory/runs"

  # Scratch repo with both master and the PR head branch.
  ( cd "$dir" && git init -q -b master >/dev/null 2>&1 \
      && git config user.email rev@example.com && git config user.name Rev \
      && printf 'base\n' > base.txt && git add -A \
      && git commit -qm 'base commit' >/dev/null 2>&1 \
      && git checkout -qb "$branch" \
      && printf 'change\n' >> base.txt && git add -A \
      && git commit -qm 'PR head change' >/dev/null 2>&1 \
      && git checkout -q master )
  local base_sha head_sha
  base_sha="$(git -C "$dir" rev-parse master)"
  head_sha="$(git -C "$dir" rev-parse "$branch")"

  # Bare remote that owns master + the PR branch (so a real push lands).
  git init -q --bare "$remote" >/dev/null 2>&1
  git -C "$dir" remote add origin "$remote"
  git -C "$dir" push -q origin master
  git -C "$dir" push -q origin "$branch:$branch"

  # Task file: already in-review with decision-06 PR tracking rows.
  cat > "$dir/docs/tasks/$slug.md" <<EOF
# Task: demo

**Status**: in-review
**Project**: software-factory

## PR tracking
- PR: #2 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/2
- Branch: $branch
- Base: master · Head: $head_sha (raised $date 12:00)
- Raised by: implementer run $orig
- Review: session $rev · verdict REQUEST_CHANGES · report docs/code-reviews/$date-$slug/
EOF

  # Original implementation session (the durable pi-native file being resumed).
  printf '{"type":"session","uuid":"%s","task":"demo"}\n' "$orig" \
    > "$dir/docs/knowledge/sessions/$orig/session.jsonl"

  # REQUEST_CHANGES review report + a review-emerged decision.
  cat > "$dir/docs/code-reviews/$date-$slug/report.md" <<EOF
# Code Review

## Verdict

REQUEST_CHANGES — fixture findings to address.
EOF
  printf '# Decision: fixture blocker\n\n## Decision\nDrop it.\n' \
    > "$dir/docs/code-reviews/$date-$slug/decisions/01-demo.md"

  # PRD for the slug (resolve_revision locates it).
  printf '**Date**: %s 10:00\n**Status**: Final\n## Testing decisions\nrun the demo verification\n' "$date" \
    > "$dir/docs/prd-queue/$date-demo.md"

  # Driver config (used only when jq is present; harmless otherwise).
  cat > "$dir/config/implementer.json" <<'CFG'
{
  "repo_map": { "software-factory": ".", "feed_analyser": "feed_analyser" },
  "model": "openrouter/deepseek/deepseek-v4-flash-0731",
  "timeout_sec": 30, "respawn_cap": 1,
  "env_allowlist": ["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "IMPLEMENTER_MODEL"],
  "image": "sandbox:latest",
  "runs_root": ".factory/runs", "archives_root": "docs/implementations",
  "liveness_interval_sec": 2, "liveness_idle_sec": 5
}
CFG

  # Helpers the driver invokes from the workspace on its success path.
  cp "$(cd "$(dirname "$0")/.." && pwd)/bin/sort-knowledge-index.py" "$dir/bin/" 2>/dev/null || true
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/transition-task.sh"; chmod +x "$dir/bin/transition-task.sh"

  local mock="$dir/mock-gh.sh" log="$dir/gh-calls.log"
  : > "$log"
  make_mock_gh_impl "$log" "$mock"

  cat > "$dir/fixture.env" <<EOF
export IMPLEMENTER_WORKSPACE="$dir"
export IMPLEMENTER_GH_BIN="$dir/mock-gh.sh"
export IMPLEMENTER_RUNS_ROOT="$dir/.factory/runs"
export IMPLEMENTER_ARCHIVES_ROOT="docs/implementations"
export IMPLEMENTER_DEFAULT_REPO="ak47-arch/workspace"
export MOCK_GH_LOG="$dir/gh-calls.log"
export MOCK_GH_VIEW_JSON='{"number":2,"title":"[factory] demo: implement","headRefName":"$branch","baseRefName":"master","headRefOid":"$head_sha","state":"OPEN","merged":false}'
export REVISE_FIXTURE="$dir"
export REVISE_REMOTE="$remote"
export REVISE_ORIG="$orig"
export REVISE_HEAD="$head_sha"
export REVISE_BRANCH="$branch"
export REVISE_SLUG="$slug"
export REVISE_DATE="$date"
EOF

  echo "$dir"
}
echo ""

# ─── Test 14: --revise <pr> --dry-run smoke — reconstructs the run dir (same
# branch, seeded session, mounted review, revision brief), reuses the original
# UUID, and simulates the pi invocation with --continue (US1+US2).
# ───────────────────────────────────────────────────────────────────────────
echo "── revise: --dry-run smoke (reconstruct + continue) ──"
RV="$(setup_revise_fixture)"
set -a; . "$RV/fixture.env"; set +a
export MOCK_PODMAN_LOG="$RV/podman-calls.log"
export IMPLEMENTER_PODMAN_BIN="$RV/mock-podman.sh"
make_mock_podman_impl "$RV/mock-podman.sh"
(
  cd "$RV"
  IMPLEMENTER_RUN_SOURCED=0 bash "$DRIVER" --revise ak47-arch/workspace#2 --dry-run
) > "$RV/revise.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "revise dry-run exits 0" || fail "revise dry-run rc=$rc: $(tail -3 "$RV/revise.out" | tr '\n' ' ')"
# Same branch checked out in the run-dir worktree.
RUNDIR="$(ls -d "$RV"/.factory/runs/demo-* 2>/dev/null | head -1)"
if [ -d "$RUNDIR/worktree" ] && [ "$(git -C "$RUNDIR/worktree" branch --show-current 2>/dev/null)" = "$REVISE_BRANCH" ]; then
  pass "revise dry-run: same branch checked out ($REVISE_BRANCH)"
else
  fail "revise dry-run: worktree branch = '$(git -C "$RUNDIR/worktree" branch --show-current 2>/dev/null)' — expected '$REVISE_BRANCH'"
fi
# Seeded sessions/ with the original session file (pi-native naming, D6).
if ls "$RUNDIR"/sessions/*_${REVISE_ORIG}.jsonl >/dev/null 2>&1; then
  pass "revise dry-run: sessions/ seeded with original session file"
else
  fail "revise dry-run: sessions/ not seeded with original session"
fi
# If a NEW uuid were minted, sessions/ would carry a different uuid; the seeded
# file uses the ORIGINAL uuid (D1 — no new UUID).
if grep -q "$REVISE_ORIG" "$RUNDIR/brief.md"; then
  pass "revise dry-run: brief reuses the ORIGINAL impl session UUID (no new UUID, D1)"
else
  fail "revise dry-run: brief does not reference the original UUID"
fi
# Review mounted as the binding spec.
if [ -f "$RUNDIR/review/report.md" ] && grep -q 'REQUEST_CHANGES' "$RUNDIR/review/report.md"; then
  pass "revise dry-run: review report mounted (REQUEST_CHANGES)"
else
  fail "revise dry-run: review report not mounted"
fi
if [ -f "$RUNDIR/review/decisions/01-demo.md" ]; then
  pass "revise dry-run: review decisions mounted"
else
  fail "revise dry-run: review decisions not mounted"
fi
# --continue + --session-dir in the (simulated) pi invocation — attempt 1.
if grep -q '<--continue>' "$MOCK_PODMAN_LOG" && grep -q '<--session-dir> <' "$MOCK_PODMAN_LOG"; then
  pass "revise dry-run: pi invocation carries --continue + --session-dir (attempt 1)"
else
  fail "revise dry-run: --continue missing from pi invocation: $(cat "$MOCK_PODMAN_LOG" | tr '\n' ' ')"
fi
# Vacuous guard: continuity is mechanically bound to the seeded session — the
# --continue flag co-occurs with the seeded original-session file.
if grep -q '<--continue>' "$MOCK_PODMAN_LOG" && ls "$RUNDIR"/sessions/*_${REVISE_ORIG}.jsonl >/dev/null 2>&1; then
  pass "revise dry-run: vacuous guard — --continue present alongside the seeded session"
else
  fail "revise dry-run: vacuous guard failed (--continue or seed missing)"
fi
rm -rf "$RV" "$REVISE_REMOTE"

# ─── Test 15: revise negatives — closed/merged PR, unresolvable slug, and a
# missing REQUEST_CHANGES review each exit 2 (US1 error contract).
# ───────────────────────────────────────────────────────────────────────────
echo "── revise: negatives (exit 2) ──"
# (a) merged PR.
RV="$(setup_revise_fixture)"; set -a; . "$RV/fixture.env"; set +a
( cd "$RV" && IMPLEMENTER_RUN_SOURCED=0 MOCK_GH_VIEW_JSON='{"number":2,"title":"[factory] demo: implement","headRefName":"fact/demo/x","headRefOid":"x","state":"MERGED","merged":true}' \
  bash "$DRIVER" --revise ak47-arch/workspace#2 --dry-run ) > "$RV/neg1.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] && grep -qi 'not open' "$RV/neg1.out" \
  && pass "revise negative: merged PR → exit 2" || fail "revise negative: merged PR rc=$rc"
rm -rf "$RV" "$REVISE_REMOTE"

# (b) unresolvable slug.
RV="$(setup_revise_fixture)"; set -a; . "$RV/fixture.env"; set +a
( cd "$RV" && IMPLEMENTER_RUN_SOURCED=0 MOCK_GH_VIEW_JSON='{"number":2,"title":"not a factory PR","headRefName":"feature/x","headRefOid":"x","state":"OPEN","merged":false}' \
  bash "$DRIVER" --revise ak47-arch/workspace#2 --dry-run ) > "$RV/neg2.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] && grep -qi 'slug' "$RV/neg2.out" \
  && pass "revise negative: unresolvable slug → exit 2" || fail "revise negative: slug rc=$rc"
rm -rf "$RV" "$REVISE_REMOTE"

# (c) missing REQUEST_CHANGES review (no binding report).
RV="$(setup_revise_fixture)"
rm -rf "$RV/docs/code-reviews"
set -a; . "$RV/fixture.env"; set +a
( cd "$RV" && IMPLEMENTER_RUN_SOURCED=0 bash "$DRIVER" --revise ak47-arch/workspace#2 --dry-run ) > "$RV/neg3.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] && grep -qi 'REQUEST_CHANGES' "$RV/neg3.out" \
  && pass "revise negative: missing REQUEST_CHANGES review → exit 2" || fail "revise negative: missing review rc=$rc"
rm -rf "$RV" "$REVISE_REMOTE"

# ─── Test 16: non-dry revise delivery — same-branch push, PR comment, NO pr
# create, Revised row recorded, task unchanged (stays in-review). (US3+US4)
# ───────────────────────────────────────────────────────────────────────────
echo "── revise: non-dry delivery (same-branch push, no pr create, Revised row) ──"
DEL="$(setup_revise_fixture)"
set -a; . "$DEL/fixture.env"; set +a
export MOCK_PODMAN_LOG="$DEL/podman-calls.log"
export IMPLEMENTER_PODMAN_BIN="$DEL/mock-podman.sh"
make_mock_podman_impl "$DEL/mock-podman.sh"
: > "$MOCK_GH_LOG"
(
  cd "$DEL"
  IMPLEMENTER_RUN_SOURCED=0 bash "$DRIVER" --revise ak47-arch/workspace#2
) > "$DEL/revise2.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "revise non-dry exits 0" || fail "revise non-dry rc=$rc: $(tail -3 "$DEL/revise2.out" | tr '\n' ' ')"

# Same-branch push: the bare remote's PR branch gained a revision commit on top
# of the ORIGINAL head (so the remote branch is a descendant of the original).
remote_head="$(git -C "$REVISE_REMOTE" rev-parse "$REVISE_BRANCH" 2>/dev/null || echo absent)"
if [ -n "$remote_head" ] && [ "$remote_head" != "$REVISE_HEAD" ] \
   && git -C "$REVISE_REMOTE" merge-base --is-ancestor "$REVISE_HEAD" "$remote_head"; then
  pass "revise non-dry: fix pushed on the SAME branch (origin/$REVISE_BRANCH advanced)"
else
  fail "revise non-dry: origin branch head='$remote_head' not descendant of '$REVISE_HEAD'"
fi
# PR comment posted; NO gh pr create.
if grep -q '<comment>' "$MOCK_GH_LOG"; then
  pass "revise non-dry: PR comment posted (gh pr comment)"
else
  fail "revise non-dry: PR comment missing: $(cat "$MOCK_GH_LOG" | tr '\n' ' ')"
fi
if grep -q '<create' "$MOCK_GH_LOG"; then
  fail "revise non-dry: gh pr create was called (D4 violation — must not raise a new PR)"
else
  pass "revise non-dry: NO gh pr create (no new PR, D4)"
fi
# Revised row on the task file, and task lifecycle unchanged (stays in-review).
if grep -q '^\- Revised: ' "$DEL/docs/tasks/$REVISE_SLUG.md"; then
  pass "revise non-dry: Revised row appended to task PR tracking (decision 06)"
else
  fail "revise non-dry: Revised row missing: $(sed -n '/## PR tracking/,$p' "$DEL/docs/tasks/$REVISE_SLUG.md" | tr '\n' ' ')"
fi
if grep -q '\*\*Status\*\*: *in-review' "$DEL/docs/tasks/$REVISE_SLUG.md"; then
  pass "revise non-dry: task stays in-review (no transition, D3)"
else
  fail "revise non-dry: task status changed"
fi
# Revision report archived next to v1 as revision-1-report.md (D5).
if ls "$DEL"/docs/implementations/*-$REVISE_SLUG/revision-1-report.md >/dev/null 2>&1; then
  pass "revise non-dry: revision-1-report.md archived in the SAME implementation dir (D5)"
else
  fail "revise non-dry: revision archive missing"
fi
rm -rf "$DEL" "$REVISE_REMOTE"

# ─── Delivery-failure tests (PRD: implementer delivery failure loud) ──────
# When delivery (branch push or PR creation) fails, the driver must route to the
# failure path instead of swallowing it into a false "Done (exit 0)": exit 1, a
# clear "FAILED:" reason, the task reverted to prd-ready, and no misleading
# success output. These run the driver's FULL `main` non-dry against a
# self-contained fixture: a mock podman fabricates the implementer report, and
# a mock transition-task actually rewrites the task status so the revert is
# observable.
write_mock_transition() {
  local dir="$1"
  cat > "$dir/bin/transition-task.sh" <<'MOCK'
#!/usr/bin/env bash
LOG="${MOCK_TRANSITION_LOG:-/dev/null}"
{ printf 'transition'; for a in "$@"; do printf ' <%s>' "$a"; done; printf '\n'; } >> "$LOG"
WS="$(cd "$(dirname "$0")/.." && pwd)"
slug="$1"; shift
to=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to) to="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$to" ] && sed -i "s/^\*\*Status\*\*:.*/**Status**: $to/" "$WS/docs/tasks/$slug.md"
exit 0
MOCK
  chmod +x "$dir/bin/transition-task.sh"
}

# Mock gh on PATH: `label` no-ops, `pr create` always fails — the delivery-failure
# seam for the failing-PR story (push_and_pr calls plain `gh`).
write_mock_gh() {
  local dir="$1"
  cat > "$dir/gh" <<'MOCK'
#!/usr/bin/env bash
LOG="${MOCK_GH_LOG:-/dev/null}"
{ printf 'gh'; for a in "$@"; do printf ' <%s>' "$a"; done; printf '\n'; } >> "$LOG"
case "$1" in
  label) exit 0 ;;
  pr) exit 1 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$dir/gh"
}

# Self-contained fixture for a NON-dry driver `main` run. origin points at a
# broken remote (mode=push-fail) or a working bare remote (mode=pr-fail).
setup_delivery_fixture() {
  local mode="$1"
  local slug="deliv"
  local dir
  dir="$(mktemp -d)"
  local remote="$dir-remote"

  mkdir -p "$dir/config" "$dir/docs/tasks" "$dir/docs/prd-queue" \
           "$dir/docs/implementations" "$dir/docs/knowledge/sessions" \
           "$dir/bin" "$dir/workspace-portability" "$dir/.factory/runs"

  ( cd "$dir" && git init -q -b master >/dev/null 2>&1 \
      && git config user.email deliv@example.com && git config user.name Deliv \
      && printf 'base\n' > base.txt && git add -A \
      && git commit -qm 'base commit' >/dev/null 2>&1 )

  if [ "$mode" = "pr-fail" ]; then
    git init -q --bare "$remote" >/dev/null 2>&1
    git -C "$dir" remote add origin "$remote"
    git -C "$dir" push -q origin master 2>/dev/null
  else
    git -C "$dir" remote add origin "$dir/no-such-remote"
  fi

  printf '**Date**: 2026-08-17 10:00\n**Status**: Final\n## Testing decisions\nrun the demo verification\n' \
    > "$dir/docs/prd-queue/2026-08-17-deliv.md"
  printf '**Status**: prd-ready\n**Project**: software-factory\n' > "$dir/docs/tasks/deliv.md"

  cat > "$dir/config/implementer.json" <<'CFG'
{
  "repo_map": { "software-factory": "." },
  "model": "openrouter/deepseek/deepseek-v4-flash-0731",
  "timeout_sec": 30, "respawn_cap": 1,
  "env_allowlist": ["OPENROUTER_API_KEY"],
  "image": "sandbox:latest",
  "runs_root": ".factory/runs", "archives_root": "docs/implementations",
  "liveness_interval_sec": 1, "liveness_idle_sec": 5
}
CFG

  cat > "$dir/workspace-portability/workspace_restore_manifest.json" <<'MF'
{ "repos": [ { "path": ".", "branch": "master" } ] }
MF

  cp "$(cd "$(dirname "$0")/.." && pwd)/bin/sort-knowledge-index.py" "$dir/bin/"
  if [ -f "$(cd "$(dirname "$0")/.." && pwd)/bin/sanitize-session.sh" ]; then
    cp "$(cd "$(dirname "$0")/.." && pwd)/bin/sanitize-session.sh" "$dir/bin/sanitize-session.sh"
  else
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/sanitize-session.sh"
    chmod +x "$dir/bin/sanitize-session.sh"
  fi
  write_mock_transition "$dir"

  echo "$dir"
}

echo "── delivery failure: branch push fails → exit 1, reverts task ──"
DELIV="$(setup_delivery_fixture push-fail)"
REMO="$DELIV-remote"
export MOCK_PODMAN_LOG="$DELIV/podman-calls.log"
export MOCK_TRANSITION_LOG="$DELIV/transition.log"
: > "$MOCK_TRANSITION_LOG"
make_mock_podman "$DELIV/mock-podman.sh"
(
  cd "$DELIV"
  HOME="$DELIV" IMPLEMENTER_RUN_SOURCED=0 IMPLEMENTER_WORKSPACE="$DELIV" \
  IMPLEMENTER_PODMAN_BIN="$DELIV/mock-podman.sh" \
  OPENROUTER_API_KEY=sk-test bash "$DRIVER" --task deliv
) > "$DELIV/out.log" 2>&1
rc=$?
[ "$rc" -eq 1 ] && pass "delivery push-fail: driver exits 1" \
  || fail "delivery push-fail: exit=$rc — expected 1: $(tail -3 "$DELIV/out.log" | tr '\n' ' ')"
grep -q "FAILED: delivery failed" "$DELIV/out.log" \
  && pass "delivery push-fail: FAILED reason printed" \
  || fail "delivery push-fail: no FAILED reason: $(grep FAILED "$DELIV/out.log" | tr '\n' ' ')"
! grep -q "Pushed branch" "$DELIV/out.log" \
  && pass "delivery push-fail: no misleading 'Pushed branch' output" \
  || fail "delivery push-fail: printed 'Pushed branch' despite failed push"
! grep -q "PR raised (tagged" "$DELIV/out.log" \
  && pass "delivery push-fail: no misleading 'PR raised' success output" \
  || fail "delivery push-fail: printed 'PR raised (tagged…)' despite failed push"
! grep -q "Done (exit 0)" "$DELIV/out.log" \
  && pass "delivery push-fail: no false 'Done (exit 0)'" \
  || fail "delivery push-fail: printed 'Done (exit 0)'"
grep -q '^\*\*Status\*\*: *prd-ready' "$DELIV/docs/tasks/deliv.md" \
  && pass "delivery push-fail: task reverted to prd-ready" \
  || fail "delivery push-fail: task status = '$(grep '^\*\*Status\*\*' "$DELIV/docs/tasks/deliv.md")'"
grep -q '<prd-ready>' "$MOCK_TRANSITION_LOG" \
  && pass "delivery push-fail: transition to prd-ready invoked" \
  || fail "delivery push-fail: no transition to prd-ready: $(cat "$MOCK_TRANSITION_LOG" | tr '\n' ' ')"
rm -rf "$DELIV" "$REMO"

echo "── delivery failure: PR creation fails → exit 1, branch pushed, reverts task ──"
DELIV="$(setup_delivery_fixture pr-fail)"
REMO="$DELIV-remote"
export MOCK_TRANSITION_LOG="$DELIV/transition.log"
export MOCK_GH_LOG="$DELIV/gh.log"
: > "$MOCK_TRANSITION_LOG"; : > "$MOCK_GH_LOG"
make_mock_podman "$DELIV/mock-podman.sh"
write_mock_gh "$DELIV"
(
  cd "$DELIV"
  HOME="$DELIV" IMPLEMENTER_RUN_SOURCED=0 IMPLEMENTER_WORKSPACE="$DELIV" \
  IMPLEMENTER_PODMAN_BIN="$DELIV/mock-podman.sh" \
  PATH="$DELIV:$PATH" \
  OPENROUTER_API_KEY=sk-test bash "$DRIVER" --task deliv
) > "$DELIV/out.log" 2>&1
rc=$?
[ "$rc" -eq 1 ] && pass "delivery pr-fail: driver exits 1" \
  || fail "delivery pr-fail: exit=$rc — expected 1: $(tail -3 "$DELIV/out.log" | tr '\n' ' ')"
grep -q "FAILED: delivery failed" "$DELIV/out.log" \
  && pass "delivery pr-fail: FAILED reason printed" \
  || fail "delivery pr-fail: no FAILED reason: $(grep FAILED "$DELIV/out.log" | tr '\n' ' ')"
grep -q "Pushed branch" "$DELIV/out.log" \
  && pass "delivery pr-fail: branch pushed (honest — left on the remote)" \
  || fail "delivery pr-fail: no 'Pushed branch' (branch should be pushed)"
! grep -q "PR raised (tagged" "$DELIV/out.log" \
  && pass "delivery pr-fail: no misleading 'PR raised' success output" \
  || fail "delivery pr-fail: printed 'PR raised (tagged…)' despite PR failure"
! grep -q "Done (exit 0)" "$DELIV/out.log" \
  && pass "delivery pr-fail: no false 'Done (exit 0)'" \
  || fail "delivery pr-fail: printed 'Done (exit 0)'"
grep -q '^\*\*Status\*\*: *prd-ready' "$DELIV/docs/tasks/deliv.md" \
  && pass "delivery pr-fail: task reverted to prd-ready" \
  || fail "delivery pr-fail: task status = '$(grep '^\*\*Status\*\*' "$DELIV/docs/tasks/deliv.md")'"
grep -q '<prd-ready>' "$MOCK_TRANSITION_LOG" \
  && pass "delivery pr-fail: transition to prd-ready invoked" \
  || fail "delivery pr-fail: no transition to prd-ready: $(cat "$MOCK_TRANSITION_LOG" | tr '\n' ' ')"
grep -q '<create>' "$MOCK_GH_LOG" \
  && pass "delivery pr-fail: gh pr create was attempted" \
  || fail "delivery pr-fail: gh pr create not called: $(cat "$MOCK_GH_LOG" | tr '\n' ' ')"
# The pushed branch genuinely landed on the bare remote (regression).
if git -C "$REMO" for-each-ref --format='%(refname)' refs/heads 2>/dev/null | grep -q 'factory/deliv/'; then
  pass "delivery pr-fail: pushed branch present on the remote"
else
  fail "delivery pr-fail: pushed branch missing from remote"
fi
rm -rf "$DELIV" "$REMO"

# ─── Summary ───────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "implementer-driver: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
  exit 1
fi
echo "All tests passed."
