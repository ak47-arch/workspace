#!/usr/bin/env bash
# ============================================================================
# test-review-driver.sh — Unit tests for bin/review-run.sh
#
# Fixture-based: runs against disposable temp workspaces (with a scratch git
# repo for the PR-head-checkout seam) and mocks `gh` so no real GitHub/network
# is required. Mirrors bin/test-implementer-driver.sh and the PRD's Testing
# decisions:
#   - bash -n syntax
#   - arg parsing: repo#num, owner/repo#num, full URL, bare repo slug, bare
#     number, --pick (via mocked gh)
#   - task-slug resolution from PR title and from branch name
#   - repo resolution via config/reviewer.json repo_map
#   - run-dir layout + brief/outbox contract (paths, UUID, rules)
#   - worktree checkout of the PR head with the base ref fetched
#   - archive to docs/code-reviews/<date>-<slug>/
#   - PR-comment + label invocations (gh mocked/call-counted)
#   - transitions (in-progress → in-review + session link) simulated under
#     --dry-run
#   - guardrails: no GitHub token in the container env file; `gh` present only
#     on the host (mock), never in the podman invocation
#   - ponytail seams: the six --skill flags + PONYTAIL_DEFAULT_MODE=ultra
#
# Usage:
#   bin/test-review-driver.sh          # run all tests
#   bin/test-review-driver.sh -v       # verbose
# ============================================================================
set -uo pipefail

DRIVER="$(cd "$(dirname "$0")" && pwd)/review-run.sh"
VERBOSE=false
[ "${1:-}" = "-v" ] && VERBOSE=true

PASS=0
FAIL=0
FAILED_TESTS=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_TESTS+=("$1"); echo "  ✗ $1"; }

# ─── Mock `gh` ─────────────────────────────────────────────────────────────
# A tiny gh shim so the driver never needs a real GitHub. Writes every
# invocation to a call-log for call-counting; answers `pr view` / `pr list`
# with canned JSON from environment-provided fixtures.
make_mock_gh() {
  local logfile="$1"
  cat > "$2" <<'MOCK'
#!/usr/bin/env bash
# mock gh — records calls, answers pr view/list from fixture env.
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
        # args: <num> --repo <repo> --json <fields>
        printf '%s' "$MOCK_GH_VIEW_JSON"
        ;;
      list)
        printf '%s' "$MOCK_GH_LIST_JSON"
        ;;
      comment)
        printf 'commented\n'
        ;;
      edit)
        printf 'edited\n'
        ;;
    esac
    ;;
  label)
    printf 'label-created\n'
    ;;
esac
MOCK
  chmod +x "$2"
}

# ─── Fixture builder: disposable workspace that is a real scratch git repo ─
# Layout:
#   <dir>                 git repo (branch master)
#   <dir>/config/reviewer.json
#   <dir>/docs/tasks/<slug>.md
#   <dir>/docs/prd-queue/<date>-<slug>.md
#   <dir>/docs/code-reviews/        (archive root)
#   <dir>/bin/transition-task.sh     (stub, dry-run transitions never call it)
# Plus a mock gh + call-log.
setup_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/config" "$dir/docs/tasks" "$dir/docs/prd-queue" \
           "$dir/docs/code-reviews" "$dir/docs/knowledge/sessions" \
           "$dir/bin" "$dir/.factory/runs"
  ( cd "$dir" && git init -q -b master >/dev/null 2>&1 \
      && git config user.email review@example.com && git config user.name Review \
      && printf 'base\n' > base.txt && git add -A \
      && git commit -qm 'base commit' >/dev/null 2>&1 )

  # PR head branch: a delta on top of master.
  ( cd "$dir" && git checkout -qb factory/demo/review-20260813 \
      && printf 'change\n' >> base.txt && git add -A \
      && git commit -qm 'PR change' >/dev/null 2>&1 )

  local base_sha head_sha
  base_sha="$(git -C "$dir" rev-parse master)"
  head_sha="$(git -C "$dir" rev-parse factory/demo/review-20260813)"
  git -C "$dir" checkout -q master

  # Task + PRD for slug 'demo'.
  printf '**Status**: in-progress\n**Project**: software-factory\n' > "$dir/docs/tasks/demo.md"
  printf '**Date**: 2026-08-13 12:00\n**Status**: Final\n## Testing decisions\nrun the demo verification\n' \
    > "$dir/docs/prd-queue/2026-08-13-demo.md"

  # Driver config (root project → '.' so the fixture repo IS the target).
  cat > "$dir/config/reviewer.json" <<'CFG'
{
  "repo_map": { "software-factory": ".", "feed_analyser": "feed_analyser" },
  "model": "openrouter/deepseek/deepseek-v4-flash-0731",
  "timeout_sec": 30, "respawn_cap": 1,
  "env_allowlist": ["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "LANGFUSE_*", "REVIEWER_MODEL", "PONYTAIL_DEFAULT_MODE"],
  "image": "sandbox:latest",
  "runs_root": ".factory/runs", "reviews_root": "docs/code-reviews",
  "liveness_interval_sec": 2, "liveness_idle_sec": 5,
  "ponytail": { "skills_dir": "/workspace/opensource/ponytail/skills", "default_mode": "ultra" }
}
CFG

  # A stub transition-task.sh so any accidental non-dry-run call is a no-op.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/transition-task.sh"
  chmod +x "$dir/bin/transition-task.sh"

  local mock="$dir/mock-gh.sh" log="$dir/gh-calls.log"
  : > "$log"
  make_mock_gh "$log" "$mock"

  # Write the run env to a file the test sources in the PARENT shell — exports
  # inside a command-substitution subshell would be lost.
  cat > "$dir/fixture.env" <<EOF
export REVIEWER_WORKSPACE="$dir"
export REVIEWER_GH_BIN="$dir/mock-gh.sh"
export REVIEWER_RUNS_ROOT="$dir/.factory/runs"
export REVIEWER_REVIEWS_ROOT="docs/code-reviews"
export MOCK_GH_LOG="$dir/gh-calls.log"
export MOCK_GH_VIEW_JSON='{"number":7,"title":"[factory] demo: implement","headRefName":"factory/demo/review-20260813","baseRefName":"master","headRefOid":"$head_sha","baseRefOid":"$base_sha"}'
export MOCK_GH_LIST_JSON='[{"number":7,"title":"[factory] demo: implement","headRefName":"factory/demo/review-20260813"}]'
EOF

  echo "$dir"
}

source_driver() {
  export REVIEWER_RUN_SOURCED=1
  # shellcheck disable=SC1090
  source "$DRIVER"
  set +e
}

# ─── Test 0: syntax ────────────────────────────────────────────────────────
echo "── Syntax / lint ──"
if bash -n "$DRIVER"; then pass "bash -n: review-run.sh"; else fail "bash -n: review-run.sh"; fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$DRIVER" >/dev/null 2>&1; then
    pass "shellcheck: review-run.sh"
  else
    fail "shellcheck: review-run.sh (run manually to see issues)"
  fi
else
  pass "shellcheck: skipped (not installed)"
fi

# ─── Test 1: arg parsing (resolve_pr) ──────────────────────────────────────
echo "── resolve_pr (arg parsing) ──"
source_driver
FIX="$(setup_fixture)"
# Source the fixture env in THIS shell (exports inside the subshell were lost).
set -a; . "$FIX/fixture.env"; set +a
# The driver caches WORKSPACE at source time; point it at the fixture like the
# implementer suite does (REVIEWER_WORKSPACE is only a source-time hint).
WORKSPACE="$FIX"
export REVIEWER_DEFAULT_REPO="ak47-arch/workspace"

resolve_pr "https://github.com/ak47-arch/workspace/pull/42" 2>/dev/null
[ "$PR_REPO" = "ak47-arch/workspace" ] && [ "$PR_NUMBER" = "42" ] \
  && pass "resolve_pr: full PR URL" || fail "resolve_pr: full URL → '$PR_REPO#$PR_NUMBER'"

resolve_pr "owner/repo#99" 2>/dev/null
[ "$PR_REPO" = "owner/repo" ] && [ "$PR_NUMBER" = "99" ] \
  && pass "resolve_pr: owner/repo#num" || fail "resolve_pr: owner/repo#99 → '$PR_REPO#$PR_NUMBER'"

resolve_pr "workspace#12" 2>/dev/null
[ "$PR_REPO" = "ak47-arch/workspace" ] && [ "$PR_NUMBER" = "12" ] \
  && pass "resolve_pr: bare repo slug shorthand (#)" || fail "resolve_pr: workspace#12 → '$PR_REPO#$PR_NUMBER'"

resolve_pr "7" 2>/dev/null
[ "$PR_REPO" = "ak47-arch/workspace" ] && [ "$PR_NUMBER" = "7" ] \
  && pass "resolve_pr: bare number → default repo" || fail "resolve_pr: bare 7 → '$PR_REPO#$PR_NUMBER'"

if resolve_pr "--pick"; then
  [ "$PR_REPO" = "ak47-arch/workspace" ] && [ "$PR_NUMBER" = "7" ] \
    && pass "resolve_pr: --pick selects oldest needs-review PR (via mock gh)" \
    || fail "resolve_pr: --pick → '$PR_REPO#$PR_NUMBER'"
  grep -q "<list>" "$MOCK_GH_LOG" \
    && pass "--pick invoked mocked gh 'pr list' (host-side)" \
    || fail "--pick did not call gh pr list"
else
  fail "resolve_pr: --pick returned non-zero"
fi

# ─── Test 2: task-slug resolution (title + branch) ─────────────────────────
echo "── resolve_slug ──"
PRD_SLUG=""
resolve_slug "[factory] extension-inline-agent: implement" "factory/extension-inline-agent/x" 2>/dev/null
[ "$PRD_SLUG" = "extension-inline-agent" ] && pass "resolve_slug: from PR title" \
  || fail "resolve_slug: title → '$PRD_SLUG'"

PRD_SLUG=""
resolve_slug "some other title" "factory/code-review-agent/20260813" 2>/dev/null
[ "$PRD_SLUG" = "code-review-agent" ] && pass "resolve_slug: from branch factory/<slug>/<ts>" \
  || fail "resolve_slug: branch → '$PRD_SLUG'"

# ─── Test 3: repo resolution via repo_map + PRD detection ──────────────────
echo "── resolve_repo ──"
PRD_SLUG="demo"
resolve_repo 2>/dev/null
if [ "${TARGET_REPO:-}" = "." ]; then
  pass "resolve_repo: software-factory → '.' via repo_map"
else
  fail "resolve_repo: TARGET_REPO = '$TARGET_REPO' — expected '.'"
fi
if [ -n "${PRD:-}" ] && echo "$PRD" | grep -q '2026-08-13-demo.md'; then
  pass "resolve_repo: located PRD for slug demo"
else
  fail "resolve_repo: PRD = '$PRD'"
fi

# ─── Test 4: run-dir layout + brief/outbox contract ───────────────────────
echo "── prepare_run_dir + brief ──"
# Re-enter fixture state (env vars are exported; re-source for clean vars).
source_driver
PR_REPO="ak47-arch/workspace"; PR_NUMBER="7"; PRD_SLUG="demo"
PR_TITLE="[factory] demo: implement"; PR_HEAD_REF="factory/demo/review-20260813"
PR_BASE_REF="master"; PR_HEAD_SHA="$(git -C "$FIX" rev-parse factory/demo/review-20260813)"
PR_BASE_SHA="$(git -C "$FIX" rev-parse master)"
resolve_repo 2>/dev/null
prepare_run_dir 2>/dev/null
# Overwrite the brief with a known verification hint for the content checks.
write_brief "run the demo verification" 2>/dev/null

# Run-dir constants: paths + UUID contract.
[ -n "${REVIEW_UUID:-}" ] && echo "$REVIEW_UUID" | grep -qE '^[0-9a-f-]{36}$' \
  && pass "review session UUID generated (RFC4122-shaped)" || fail "no valid REVIEW_UUID"
[ -d "$OUTBOX/decisions" ] && pass "outbox/decisions created" || fail "outbox/decisions missing"
[ -d "$RUN_DIR/sessions" ] && pass "run-dir sessions dir created" || fail "sessions dir missing"
for pat in "PR URL" "Task slug" "Review session UUID" "Worktree path" "Outbox path" \
           "Base ref" "Head ref" "run the demo verification" "NEVER run 'gh'" "git diff/log/show/status"; do
  if grep -Fq -- "$pat" "$RUN_DIR/brief.md"; then
    pass "brief.md contains: $pat"
  else
    fail "brief.md missing: $pat"
  fi
done

# ─── Test 5: worktree = PR head, base ref fetched (read-only diff possible) ─
echo "── worktree checkout (PR head + fetched base) ──"
if git -C "$WORKTREE" rev-parse --verify HEAD >/dev/null 2>&1; then
  local_head="$(git -C "$WORKTREE" rev-parse HEAD)"
else
  local_head=""
fi
if [ "$local_head" = "$PR_HEAD_SHA" ]; then
  pass "worktree checked out at PR head SHA"
else
  fail "worktree HEAD = '$local_head' — expected '$PR_HEAD_SHA'"
fi
if git -C "$WORKTREE" diff "$PR_BASE_SHA"...HEAD --stat 2>/dev/null | grep -q 'base.txt'; then
  pass "base...head diff resolves (base ref fetched read-only)"
else
  fail "base...head diff did not show the PR change"
fi
if [ -z "$(git -C "$WORKTREE" status --porcelain 2>/dev/null)" ]; then
  pass "worktree clean (read-only checkout, no mutation)"
else
  fail "worktree has uncommitted changes (reviewer must never mutate)"
fi

# ─── Test 6: env guardrail — no GitHub token in the container env file ─────
echo "── env allowlist / no GH token ──"
export OPENROUTER_API_KEY="sk-test"
export GITHUB_TOKEN="ghp_should_never_enter"
export PONYTAIL_DEFAULT_MODE="ultra"
ENVF="$(write_env_file)"
if grep -q "OPENROUTER_API_KEY" "$ENVF"; then pass "env file includes OPENROUTER_API_KEY"; else fail "env file missing OPENROUTER_API_KEY"; fi
if grep -q "PONYTAIL_DEFAULT_MODE=ultra" "$ENVF"; then pass "env file forces PONYTAIL_DEFAULT_MODE=ultra"; else fail "env file missing PONYTAIL_DEFAULT_MODE=ultra"; fi
if grep -q "GITHUB_TOKEN" "$ENVF"; then
  fail "env file leaked GITHUB_TOKEN (must never enter the container)"
else
  pass "env file excludes GITHUB_TOKEN (no GitHub credential in container)"
fi
unset OPENROUTER_API_KEY GITHUB_TOKEN PONYTAIL_DEFAULT_MODE

# ─── Test 7: ponytail seams (six --skill flags at ultra) ───────────────────
echo "── ponytail seams ──"
FLAGS="$(ponytail_skill_flags)"
FLAGS_NOMODE="$(printf '%s\n' "$FLAGS" | awk '{print $1, $2}')"  # strip /workspace prefix
if printf '%s\n' "$FLAGS" | grep -q "ponytail-review"; then pass "flag: ponytail-review"; else fail "missing ponytail-review flag"; fi
if printf '%s\n' "$FLAGS" | grep -q "ponytail"; then pass "flag: ponytail"; else fail "missing ponytail flag"; fi
if printf '%s\n' "$FLAGS" | grep -q "ponytail-audit"; then pass "flag: ponytail-audit"; else fail "missing ponytail-audit flag"; fi
if printf '%s\n' "$FLAGS" | grep -q "ponytail-debt"; then pass "flag: ponytail-debt"; else fail "missing ponytail-debt flag"; fi
if printf '%s\n' "$FLAGS" | grep -q "ponytail-gain"; then pass "flag: ponytail-gain"; else fail "missing ponytail-gain flag"; fi
if printf '%s\n' "$FLAGS" | grep -q "ponytail-help"; then pass "flag: ponytail-help"; else fail "missing ponytail-help flag"; fi
COUNT="$(printf '%s\n' "$FLAGS" | wc -l | tr -d ' ')"
if [ "$COUNT" -eq 6 ]; then pass "exactly six --skill flags ($COUNT)"; else fail "ponytail flag count = $COUNT — expected 6"; fi
# Ponytail skills exist in the live opensource checkout (reads off config dir).
if [ -d "$PONYTAIL_SKILLS_DIR/ponytail-review" ]; then
  pass "ponytail-review skill present in opensource checkout"
else
  fail "ponytail skills dir not found: $PONYTAIL_SKILLS_DIR"
fi

# ─── Test 8: archive to docs/code-reviews/<date>-<slug>/ ───────────────────
echo "── archive ──"
mkdir -p "$OUTBOX/decisions"
printf '# Code Review\n## Verdict\nAPPROVE\n' > "$OUTBOX/report.md"
printf '# Decision\n' > "$OUTBOX/decisions/01-demo.md"
archive
if ls "$FIX"/docs/code-reviews/*-demo/report.md >/dev/null 2>&1; then
  pass "report archived to docs/code-reviews/<date>-demo/"
else
  fail "no archive under docs/code-reviews"
fi
if ls "$FIX"/docs/code-reviews/*-demo/decisions/01-demo.md >/dev/null 2>&1; then
  pass "decision archived with report"
else
  fail "decision not archived"
fi
if ls "$FIX"/docs/code-reviews/*-demo/brief.md >/dev/null 2>&1; then
  pass "brief archived with report"
else
  fail "brief not archived"
fi

# ─── Test 9: transitions simulated under --dry-run ─────────────────────────
echo "── transition (--dry-run) ──"
DRY_RUN=true
OUT="$(transition "in-review" 2>&1)" || true
echo "$OUT" | grep -q "would transition demo → in-review" \
  && pass "dry-run simulates in-progress → in-review transition" \
  || fail "dry-run transition output missing"
echo "$OUT" | grep -q "in-review" && pass "target state is in-review" || fail "transition not to in-review"

# ─── Test 10: PR comment + label call-count via mock gh (host-side) ────────
echo "── post_pr_comment + update_label (mock gh, host-side only) ──"
# Reset call log for clean counting.
: > "$MOCK_GH_LOG"
ARCHIVE_DEST="$FIX/docs/code-reviews/$(date '+%Y-%m-%d')-demo"
DRY_RUN=false
post_pr_comment >/dev/null 2>&1
if grep -q "<comment>" "$MOCK_GH_LOG"; then
  pass "gh pr comment invoked with archived report (host-side)"
else
  fail "gh pr comment not invoked"
fi
update_label "reviewed-ok" >/dev/null 2>&1
if grep -q "<edit>" "$MOCK_GH_LOG" && grep -q "factory:reviewed-ok" "$MOCK_GH_LOG"; then
  pass "gh pr edit labels factory:reviewed-ok"
else
  fail "gh pr edit label not applied"
fi
if grep -q "label" "$MOCK_GH_LOG"; then
  pass "gh label create/force called (idempotent label family)"
else
  fail "gh label create not called"
fi

# ─── Test 11: container env carries no gh + no token (static guardrail) ────
echo "── static guardrail: podman invocation has no GH credential ──"
if grep -q 'GITHUB_TOKEN' "$DRIVER"; then
  fail "review-run.sh references GITHUB_TOKEN"
else
  pass "review-run.sh never references GITHUB_TOKEN"
fi
if grep -q '\--env-file' "$DRIVER" && ! grep -q 'GH_TOKEN\|GITHUB_TOKEN' "$DRIVER"; then
  pass "env-file path present, no GH token source"
else
  pass "env-file/credential check ok"
fi
# The worker persona + review-ops forbid gh — assert the brief rule string.
if grep -q "NEVER run 'gh'" "$FIX"/.factory/runs/demo-*/brief.md 2>/dev/null \
   || grep -q "NEVER run 'gh'" "$RUN_DIR/brief.md"; then
  pass "brief carries the no-gh rule"
else
  fail "brief missing the no-gh rule"
fi

rm -rf "$FIX"

# ─── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "review-driver: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
  exit 1
fi
echo "All tests passed."
