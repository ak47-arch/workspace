#!/usr/bin/env bash
# ============================================================================
# implementer-run.sh — Host-side driver for the sandboxed implementer agent.
#
# The implementer follows a decoupled brain/hands pattern:
#   * HOST (this driver): deterministic orchestration + ALL git mutations.
#     Picks a `**Status**: Final` PRD, creates a durable host-side worktree,
#     writes a task brief, provisions the sandbox container (cattle) with
#     read-only workspace + read-write run dir, streams the implementer's
#     JSONL event output live into a host-side session log, watches liveness,
#     respawns on abnormal container death, and on success archives the run
#     report + decisions, pushes the worktree branch, and raises a PR.
#   * CONTAINER (the hands): one headless `pi` process running the
#     implementer agent inside a podman sandbox image. Holds nothing durable;
#     all state exits through git / the run dir on the host.
#
# Usage:
#   bin/implementer-run.sh [--task <slug>|--pick] [--dry-run]
#   --task <slug>   Run a specific Final PRD (default: --pick)
#   --pick          Select the oldest Final PRD not already in-progress
#   --dry-run       Produce worktree + brief + session log, but NO push, NO PR,
#                   NO workspace-root commit. State transitions are simulated.
#   --resume        (reserved) Resume an interrupted run from its run dir.
#
# Exit codes:
#   0  Success (PR raised, or dry-run completed)
#   1  Failure (partial report written, task reverted to prd-ready, no PR)
#   2  Usage / selection error (no Final PRD found, invalid slug, etc.)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test seam: IMPLEMENTER_WORKSPACE lets fixture-based tests point the driver
# at a disposable workspace without any real git context.
WORKSPACE="${IMPLEMENTER_WORKSPACE:-$SCRIPT_DIR}"
CONFIG_FILE="$WORKSPACE/config/implementer.json"

# ─── Config loading ────────────────────────────────────────────────────────
# Pull scalar values from config/implementer.json with jq; fall back to a
# here-doc default if jq is unavailable (all values mirrored).
if command -v jq >/dev/null 2>&1; then
  cfg() { jq -r "$1" "$CONFIG_FILE"; }
  MODEL="$(cfg '.model')"
  TIMEOUT_SEC="$(cfg '.timeout_sec')"
  RESPAWN_CAP="$(cfg '.respawn_cap')"
  IMAGE="$(cfg '.image')"
  RUNS_ROOT="$(cfg '.runs_root')"
  ARCHIVES_ROOT="$(cfg '.archives_root')"
  LIVENESS_INTERVAL="$(cfg '.liveness_interval_sec')"
  LIVENESS_IDLE="$(cfg '.liveness_idle_sec')"
  repo_map_path() { cfg ".repo_map[\"$1\"] // empty"; }
  env_allowed() { jq -r '.env_allowlist[]' "$CONFIG_FILE"; }
else
  MODEL="openrouter/deepseek/deepseek-v4-flash-0731"
  TIMEOUT_SEC=1800
  RESPAWN_CAP=3
  IMAGE="sandbox:latest"
  RUNS_ROOT="$HOME/.factory/runs"
  ARCHIVES_ROOT="docs/implementations"
  LIVENESS_INTERVAL=15
  LIVENESS_IDLE=300
  repo_map_path() {
    case "$1" in
      software-factory|langfuse) echo "." ;;
      feed_analyser) echo "feed_analyser" ;;
      workspace-portability) echo "workspace-portability" ;;
      survival-infrastructure) echo "survival-infrastructure" ;;
      llm) echo "llm" ;;
      headroom-pi) echo "headroom-pi" ;;
      resume) echo "resume" ;;
      emotional_architecture) echo "emotional_architecture" ;;
      *) echo "" ;;
    esac
  }
  env_allowed() { printf '%s\n' OPENROUTER_API_KEY ANTHROPIC_API_KEY \
    LANGFUSE_SECRET_KEY LANGFUSE_PUBLIC_KEY LANGFUSE_BASE_URL IMPLEMENTER_MODEL; }
fi

RUNS_ROOT="${RUNS_ROOT/#\~/$HOME}"

# ─── Helpers ───────────────────────────────────────────────────────────────
now_ts() { date '+%Y%m%d-%H%M%S'; }
now_human() { date '+%Y-%m-%d %H:%M'; }
new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}

die() { echo "ERROR: $*" >&2; exit 2; }

# Task slug from a PRD filename: yyyy-mm-dd-<slug>.md → <slug>
slug_from_prd() { basename "$1" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//'; }

# ─── Arg parsing ───────────────────────────────────────────────────────────
TASK=""
DRY_RUN=false
MODE_FLAG="--pick"

while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="$2"; MODE_FLAG=""; shift 2 ;;
    --pick) MODE_FLAG="--pick"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --resume) echo "WARN: --resume is reserved; not implemented in v1." >&2; shift ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ─── resolve_prd(): select one Final PRD ───────────────────────────────────
# - $MODE_FLAG=--pick: oldest `**Status**: Final` in docs/prd-queue/, skipping
#   tasks already in-progress. Oldest = smallest date prefix in filename.
# - --task: the PRD whose filename carries the given slug.
resolve_prd() {
  local prd=""
  if [ -n "$MODE_FLAG" ]; then
    local candidate
    local best=""
    for candidate in "$WORKSPACE"/docs/prd-queue/*.md; do
      [ -f "$candidate" ] || continue
      grep -q '^\*\*Status\*\*: *Final' "$candidate" || continue
      local slug; slug="$(slug_from_prd "$candidate")"
      # Skip tasks already in-progress (a concurrent implementer owns them).
      if grep -q '^\*\*Status\*\*: *in-progress' "$WORKSPACE/docs/tasks/$slug.md" 2>/dev/null; then
        echo "  [pick] skipping $slug (task already in-progress)" >&2
        continue
      fi
      [ -z "$best" ] && best="$candidate"
      # Filename date prefix sorts oldest-first; pick smallest.
      if [ "$(basename "$candidate")" \< "$(basename "$best")" ]; then
        best="$candidate"
      fi
    done
    prd="$best"
  else
    prd="$(ls "$WORKSPACE"/docs/prd-queue/*-"$TASK.md" 2>/dev/null | head -1 || true)"
  fi

  if [ -z "$prd" ] || [ ! -f "$prd" ]; then
    if [ -n "$MODE_FLAG" ]; then
      die "No pickable 'Final' PRD in docs/prd-queue/ (all done or in-progress)."
    fi
    die "No PRD found for slug '$TASK' in docs/prd-queue/"
  fi

  # Must be Final to be routeable.
  if ! grep -q '^\*\*Status\*\*: *Final' "$prd"; then
    die "PRD $prd is not 'Final' (not past the review gate)."
  fi

  echo "  Selected PRD: $(basename "$prd")" >&2
  PRD="$prd"
  PRD_SLUG="$(slug_from_prd "$prd")"
  if [ -n "$TASK" ]; then
    PRD_SLUG="$TASK"
  fi
}

# ─── resolve_repo(): task Project → repo path via repo_map ─────────────────
resolve_repo() {
  local task_file="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  [ -f "$task_file" ] || die "Task file not found: $task_file"
  PROJECT="$(grep -m1 '^\*\*Project\*\*:' "$task_file" | sed 's/^\*\*Project\*\*: *//')"
  if [ -z "$PROJECT" ]; then
    PROJECT="software-factory"
  fi
  TARGET_REPO="$(repo_map_path "$PROJECT")"
  if [ -z "$TARGET_REPO" ]; then
    # Unmapped project: default to workspace root.
    echo "  [warn] project '$PROJECT' not in repo_map; defaulting to workspace root." >&2
    TARGET_REPO="."
  fi
  echo "  Resolved project '$PROJECT' → repo '$TARGET_REPO'" >&2

  # Manifest branch for the target repo (via workspace-portability manifest).
  MANIFEST_BRANCH="$(python3 - "$TARGET_REPO" "$WORKSPACE" <<'PYEOF'
import json, sys, os
repo, workspace = sys.argv[1], sys.argv[2]
manifest = os.path.join(workspace, "workspace-portability", "workspace_restore_manifest.json")
try:
    with open(manifest) as f:
        data = json.load(f)
    for r in data.get("repos", []):
        if r.get("path") == repo:
            print(r.get("branch", "master"))
            sys.exit(0)
except Exception:
    pass
print("master")
PYEOF
  )"
  echo "  Target repo manifest branch: $MANIFEST_BRANCH" >&2
}

# ─── prepare_run_dir(): worktree + outbox + brief ──────────────────────────
prepare_run_dir() {
  local ts; ts="$(now_ts)"
  IMPL_UUID="$(new_uuid)"
  RUN_DIR="$RUNS_ROOT/$PRD_SLUG-$ts"
  WORKTREE="$RUN_DIR/worktree"
  OUTBOX="$RUN_DIR/outbox"
  SESSION_LOG="$RUN_DIR/session.jsonl"
  WORKTREE="$RUN_DIR/worktree"
  mkdir -p "$OUTBOX/decisions" "$RUN_DIR/sessions"
  echo "  Run dir: $RUN_DIR" >&2
  echo "  Impl session UUID: $IMPL_UUID" >&2

  # Target repo, resolved to an absolute path on the host (for clone + push).
  local src_repo; src_repo="$WORKSPACE/$TARGET_REPO"
  [ -d "$src_repo/.git" ] || die "Target repo not a git repo: $src_repo"

  # Self-contained clone in the run dir — NOT a host git worktree. A host
  # `git worktree .git` points at the host repo's common dir, which lives on
  # the read-only /workspace mount and therefore cannot be committed into from
  # inside the container. A full clone keeps all git metadata inside the
  # writable /sandbox run dir, so the implementer commits natively.
  local branch="factory/$PRD_SLUG/$ts"
  git clone --quiet --local "$src_repo" "$WORKTREE" 2>/dev/null \
    || git clone --quiet "$src_repo" "$WORKTREE"
  git -C "$WORKTREE" checkout -q -B "$branch" "origin/$MANIFEST_BRANCH" 2>/dev/null \
    || git -C "$WORKTREE" checkout -q -B "$branch" "$MANIFEST_BRANCH"
  # Keep a pristine manifest branch ref so the push below can target it.
  git -C "$WORKTREE" branch "refs/heads/origin-$MANIFEST_BRANCH" \
    "origin/$MANIFEST_BRANCH" 2>/dev/null || true
  # Point origin at the REAL remote (clone --local sets it to the local path).
  local real_url
  real_url="$(git -C "$src_repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$real_url" ]; then
    git -C "$WORKTREE" remote set-url origin "$real_url"
  fi
  WORKTREE_BRANCH="$branch"
  echo "  Worktree clone: $WORKTREE (branch $branch, base $MANIFEST_BRANCH)" >&2

  # Build the verification-commands hint from the PRD's Testing decisions.
  local verify_hint="See the PRD `## Testing decisions` for the acceptance commands. Run them inside the worktree as the PRD specifies."

  write_brief "$verify_hint"
}

write_brief() {
  cat > "$RUN_DIR/brief.md" <<EOF
# Implementer Task Brief

- **PRD path**: ${PRD#/workspace/} (read-only; also below)
- **Task slug**: $PRD_SLUG
- **Impl session UUID**: $IMPL_UUID
- **Worktree path** (read-write; your working directory): /sandbox/worktree
- **Outbox path** (write results here): /sandbox/outbox

## Rules (binding)

1. Implement EVERY user story in the PRD, one story/unit at a time.
2. Work ONLY inside /sandbox/worktree. Your edits are already durable on the
   host's disk via this mount — you do NOT need to commit anything.
3. Do NOT run ANY git command (no init/add/commit/stash/push/pull/checkout).
   The host driver performs the single commit, push, and PR at the end.
4. You CANNOT modify docs/tasks/, docs/tasks.txt, or docs/prd-queue/ — those
   live in the read-only /workspace mount. Do not attempt to bypass this.
5. Do NOT write secrets, keys, or GitHub credentials anywhere.
6. Do NOT run builds that require network secrets you don't have.

## Verification

$1
- State evidence for each story (what you changed and how it is verified).

## Completion

Write /sandbox/outbox/report.md (per-story done/not-done + evidence +
verification results + UAT hand-off list) and any emerged decisions to
/sandbox/outbox/decisions/NN-<slug>.md (structured decision format), then exit 0.
On partial failure, still write the report and exit 1.
EOF
  echo "  Brief written: $RUN_DIR/brief.md" >&2
}

# ─── transition(): lifecycle transition (simulated under --dry-run) ────────
transition() {
  local to="$1"; shift
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would transition $PRD_SLUG → $to" >&2
    return 0
  fi
  local session_flag=""
  if [ "$to" = "in-progress" ]; then
    session_flag="--session $IMPL_UUID:implementation"
  fi
  "$WORKSPACE/bin/transition-task.sh" "$PRD_SLUG" --to "$to" $session_flag "$@"
}

# ─── Write impl session header ─────────────────────────────────────────────
write_session_header() {
  mkdir -p "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"
  if [ ! -f "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl" ]; then
    {
      printf '{"type":"session","uuid":"%s","task":"%s","project":"%s","driver":"implementer-run.sh","start":"%s"}\n' \
        "$IMPL_UUID" "$PRD_SLUG" "$PROJECT" "$(now_human)"
    } > "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl"
  fi
  echo "  Session log: docs/knowledge/sessions/$IMPL_UUID/session.jsonl" >&2
}

# ─── Build filtered secrets env-list ───────────────────────────────────────
write_env_file() {
  local envfile="$RUN_DIR/secrets.env"
  : > "$envfile"
  chmod 600 "$envfile"
  local name
  while read -r name; do
    [ -z "$name" ] && continue
    if [ -n "${!name:-}" ]; then
      printf '%s=%s\n' "$name" "${!name}" >> "$envfile"
    fi
  done < <(env_allowed)
  # Env must contain ONLY LLM + Langfuse credentials — never GH tokens.
  echo "$envfile"
}

# ─── run_container(): one podman attempt, streamed live ────────────────────
# Returns 0 on implementer success (report present), 1 on container/impl failure.
run_container() {
  local attempt="$1"
  local envfile; envfile="$(write_env_file)"

  local model_arg=()
  if [ -n "${IMPLEMENTER_MODEL:-}" ]; then
    model_arg=(--model "$IMPLEMENTER_MODEL")
  else
    model_arg=(--model "$MODEL")
  fi

  local container_out="$RUN_DIR/container-$attempt.log"

  echo "  [attempt $attempt/$RESPAWN_CAP] podman run $IMAGE ..." >&2

  # Continuity is native: pi persists its session to the host mount under the
  # run's IMPL_UUID, and a respawn reopens that SAME session-id, so the fresh
  # container continues the existing conversation (no PROGRESS.md needed).
  local directive
  if [ "$attempt" -eq 1 ]; then
    directive="Execute your implementer run contract now. Read /sandbox/brief.md and the PRD it references, implement every user story in /sandbox/worktree (do NOT run any git commands — the host owns git), run the PRD verification commands, then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  else
    directive="Resume your interrupted implementer run. You were killed mid-run; this container continues the SAME session, and your edits are already on disk in /sandbox/worktree. Continue from where you left off — do NOT restart from scratch. Finish implementing every story per /sandbox/brief.md (do NOT run any git commands — the host owns git), run verification, then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  fi

  local exit_code=0
  # Live-stream container stdout into the session log while it runs.
  (
    exec podman run --rm --network=host \
      -v "$WORKSPACE:/workspace:ro" \
      -v "$RUN_DIR:/sandbox" \
      --env-file "$envfile" \
      "$IMAGE" \
      pi --mode json -p \
        --session-dir /sandbox/sessions \
        --session-id "$IMPL_UUID" \
        --append-system-prompt /sandbox/brief.md \
        --append-system-prompt /workspace/.pi/agents/implementer.md \
        "${model_arg[@]}" \
        "$directive"
  ) > "$container_out" 2>&1 & local pid=$!

  # Liveness watch: tail-running, plus a hard overall timeout. The idle watchdog
  # keys on new bytes; a long-running tool (e.g. `... | tail`) emits nothing until
  # it finishes, so we skip the idle-kill while a tool_execution is open — the
  # hard timeout below still bounds the run.
  local deadline=$(( $(date +%s) + TIMEOUT_SEC ))
  local last_activity=0
  local last_size=0
  local tool_open=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ $(date +%s) -ge "$deadline" ]; then
      echo "  [timeout] run exceeded ${TIMEOUT_SEC}s — terminating container." >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    # Append any new bytes since last poll to the session log (live stream).
    if [ -f "$container_out" ]; then
      local size; size=$(wc -c < "$container_out")
      if [ "$size" -gt "$last_size" ]; then
        local slice; slice=$(tail -c +$((last_size+1)) "$container_out")
        printf '%s' "$slice" >> "$SESSION_LOG"
        # Track whether a tool is currently executing (start minus end).
        local s; s=$(printf '%s' "$slice" | grep -c '"type":"tool_execution_start"' || true)
        local e; e=$(printf '%s' "$slice" | grep -c '"type":"tool_execution_end"' || true)
        tool_open=$((tool_open + s - e)); [ "$tool_open" -lt 0 ] && tool_open=0
        last_size="$size"
        last_activity=$(date +%s)
      fi
    fi
    # Idle watchdog: no new output for LIVENESS_IDLE seconds while idle (no tool
    # execution open) → unhealthy. A quiet-but-running tool is left alone.
    if [ "$tool_open" -eq 0 ] && [ "$last_activity" -ne 0 ] && [ $(( $(date +%s) - last_activity )) -gt "$LIVENESS_IDLE" ]; then
      echo "  [liveness] no output for ${LIVENESS_IDLE}s (no tool running) — treating as stuck." >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep "$LIVENESS_INTERVAL"
  done
  wait "$pid" || exit_code=$?

  # Drain final output.
  if [ -f "$container_out" ]; then
    local size; size=$(wc -c < "$container_out")
    if [ "$size" -gt "$last_size" ]; then
      tail -c +$((last_size+1)) "$container_out" >> "$SESSION_LOG"
    fi
  fi

  if [ -f "$OUTBOX/report.md" ]; then
    echo "  [attempt $attempt] implementer completed with report; exit=$exit_code" >&2
    return 0
  fi
  echo "  [attempt $attempt] implementer did not complete; exit=$exit_code" >&2
  return 1
}

# ─── archive(): copy outbox → docs/implementations/<date>-<slug>/ ──────────
archive() {
  local ts; ts="$(date '+%Y-%m-%d')"
  local dest="$WORKSPACE/$ARCHIVES_ROOT/$ts-$PRD_SLUG"
  mkdir -p "$dest/decisions"
  if [ -f "$OUTBOX/report.md" ]; then
    cp "$OUTBOX/report.md" "$dest/report.md"
  fi
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$dest/decisions/" 2>/dev/null || true
  fi
  # Keep a copy of the brief for auditability.
  cp "$RUN_DIR/brief.md" "$dest/brief.md"
  echo "  Archived run artifacts → $dest" >&2
  ARCHIVE_DEST="$dest"
}

# ─── append index entries via the deterministic sorter ─────────────────────
append_decisions_to_index() {
  # The driver (never the model) owns docs/knowledge/index.md. First mirror any
  # outbox decisions into the impl session dir (the driver archives them there
  # too, following the knowledge-base convention), then add index links by
  # re-running the deterministic sorter.
  local sess_dir="$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"
  mkdir -p "$sess_dir/decisions"
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$sess_dir/decisions/" 2>/dev/null || true
  fi
  local idx="$WORKSPACE/docs/knowledge/index.md"
  local proj="$PROJECT"
  # Ensure a project section exists, then insert entry lines (driver-only).
  if ! grep -q "^### $proj" "$idx"; then
    printf '\n### %s\n' "$proj" >> "$idx"
  fi
  local d
  for d in "$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID"/decisions/*.md; do
    [ -f "$d" ] || continue
    local base; base="$(basename "$d")"
    local title; title="$(echo "$base" | sed -E 's/^[0-9]+-//; s/\.md$//; s/-/ /g')"
    if ! grep -Fq "sessions/$IMPL_UUID/decisions/$base" "$idx"; then
      # Insert under the project section (driver-side append).
      python3 - "$idx" "$proj" "$title" "$IMPL_UUID" "$base" <<'PYEOF'
import sys
path, proj, title, uuid, base = sys.argv[1:6]
with open(path) as f:
    lines = f.read().split('\n')
out = []
inserted = False
for line in lines:
    out.append(line)
    if line.strip() == f'### {proj}' and not inserted:
        out.append(f'- [{title}](sessions/{uuid}/decisions/{base})')
        inserted = True
with open(path, 'w') as f:
    f.write('\n'.join(out) + '\n')
PYEOF
    fi
  done
  python3 "$WORKSPACE/bin/sort-knowledge-index.py" >/dev/null
  echo "  Appended + re-sorted decision index entries." >&2
}

# ─── push + PR (driver-only; skipped under --dry-run) ──────────────────────
push_and_pr() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would push branch $WORKTREE_BRANCH and raise a PR against $MANIFEST_BRANCH" >&2
    return 0
  fi
  # Host authors the single commit from the implementer's files (the implementer
  # never touches git). Commit everything the model wrote in the worktree.
  git -C "$WORKTREE" add -A
  git -C "$WORKTREE" diff --cached --quiet \
    || git -C "$WORKTREE" commit -q -m "implementer($PRD_SLUG): run $IMPL_UUID [factory]"
  echo "  Host-authored worktree commit on $WORKTREE_BRANCH" >&2
  # Push the worktree branch (commits live in the run-dir clone, not src).
  # origin in the clone already points at the real remote.
  git -C "$WORKTREE" push -u origin "$WORKTREE_BRANCH"
  echo "  Pushed branch $WORKTREE_BRANCH" >&2

  # Raise the PR with title/body derived from the brief + report.
  local title="[factory] ${PRD_SLUG}: implementer run (${now_human})"
  local body_file="$RUN_DIR/pr-body.md"
  {
    echo "## Implementer Run"
    echo ""
    echo "Task: \`${PRD_SLUG}\`"
    echo "Impl session: \`${IMPL_UUID}\`"
    echo ""
    echo "### Report"
    echo ""
    if [ -f "$ARCHIVE_DEST/report.md" ]; then cat "$ARCHIVE_DEST/report.md"; fi
  } > "$body_file"

  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not installed; PR skipped (branch already pushed)." >&2; return 1; }
  # Derive the GitHub repo slug from the source repo's origin URL.
  local gh_repo
  gh_repo="$(git -C "$WORKSPACE/$TARGET_REPO" remote get-url origin 2>/dev/null \
    | sed -E 's#.*/([^/]+)\.git#\1#; s#.*/([^/]+)#\1#' )"
  [ -z "$gh_repo" ] && gh_repo="workspace"
  gh pr create \
    --repo "ak47-arch/$gh_repo" \
    --base "$MANIFEST_BRANCH" --head "$WORKTREE_BRANCH" \
    --title "$title" --body-file "$body_file"
  echo "  PR raised." >&2
}

# ─── failure path ──────────────────────────────────────────────────────────
fail_run() {
  local reason="$1"
  echo "  FAILED: $reason" >&2
  if [ -d "$OUTBOX" ] && [ -f "$OUTBOX/report.md" ]; then
    archive
  elif [ -d "$OUTBOX" ]; then
    # Write a partial report so the failure is durable.
    cp "$RUN_DIR/brief.md" "$OUTBOX/partial-report.md" 2>/dev/null || true
    echo "# Partial report" > "$OUTBOX/report.md"
    echo "" >> "$OUTBOX/report.md"
    echo "Run failed: $reason" >> "$OUTBOX/report.md"
    archive
  fi
  transition "prd-ready"
  exit 1
}

# ─── main ──────────────────────────────────────────────────────────────────
# Guard: when sourced by a test harness, do not auto-run main.
if [ "${IMPLEMENTER_RUN_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

echo "=== implementer-run.sh ==="
echo "  dry-run: $DRY_RUN | mode: ${MODE_FLAG:---task $TASK}"

resolve_prd
resolve_repo
prepare_run_dir
transition "in-progress"
write_session_header

# ── Run the container with respawn (cattle) ────────────────────────────────
local_result=1
attempt=1
while [ $attempt -le "$RESPAWN_CAP" ]; do
  if run_container "$attempt"; then
    local_result=0
    break
  fi
  if [ $attempt -lt "$RESPAWN_CAP" ]; then
    echo "  Respawn: attempt $attempt failed; starting fresh container against same run dir." >&2
  fi
  attempt=$((attempt+1))
done

# Finalize the knowledge copy of the session with the full streamed transcript
# (the startup header above is just a stub). The pi-native session also lives on
# the host mount under the run dir; prefer it, falling back to the tee transcript.
finalize_session_copy() {
  local sess="$WORKSPACE/docs/knowledge/sessions/$IMPL_UUID/session.jsonl"
  local native="$RUN_DIR/sessions/$IMPL_UUID.jsonl"
  if [ -s "$native" ]; then
    cp "$native" "$sess"
  elif [ -s "$SESSION_LOG" ]; then
    cp "$SESSION_LOG" "$sess"
  fi
}
finalize_session_copy

if [ "$local_result" -eq 0 ]; then
  echo "=== Implementer success — archiving + delivering ===" >&2
  archive
  append_decisions_to_index
  # Link the impl session on the task file (driver-side via transition tooling).
  if [ "$DRY_RUN" != true ]; then
    transition "in-progress"
  fi
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would commit+push workspace root, push branch, and raise PR" >&2
  else
    # Commit + push the workspace root (archive, index, task-file session link).
    ( cd "$WORKSPACE" && git add "$ARCHIVES_ROOT" docs/knowledge/sessions/$IMPL_UUID \
        docs/knowledge/index.md docs/tasks/$PRD_SLUG.md docs/tasks.txt 2>/dev/null || true
      git diff --cached --quiet || git commit -m "implementer($PRD_SLUG): archive run report + decisions [impl $IMPL_UUID]" )
    push_and_pr || true
  fi
  echo "Done (exit 0)."
  exit 0
else
  fail_run "container/implementer failed after ${RESPAWN_CAP} attempts"
fi
