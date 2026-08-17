#!/usr/bin/env bash
# ============================================================================
# review-run.sh — Host-side driver for the sandboxed code-reviewer agent.
#
# The code-reviewer is the post-implementation gate on the assembly line: the
# sibling of the implementer that picks up a raised PR and checks it against its
# PRD. It mirrors the implementer's decoupled brain/hands pattern:
#   * HOST (this driver): deterministic orchestration + ALL git mutations + ALL
#     `gh` calls (resolve PR/repo, post the PR comment, manage labels, lifecycle
#     transitions). Resolves the PR → repo → task slug → PRD, creates a durable
#     host-side run dir, checks out the PR head (base ref fetched) into the
#     worktree, writes a review brief, provisions the sandbox container with the
#     six ponytail skills + PONYTAIL_DEFAULT_MODE=ultra, streams the worker's
#     JSONL event output, respawns on abnormal death, and on success archives
#     the review report to docs/code-reviews/<date>-<slug>/, posts it to the PR,
#     and transitions the task in-progress → in-review.
#   * CONTAINER (the hands): one headless `pi` process running the code-reviewer
#     agent inside a podman sandbox image. It is READ-ONLY: it may run read-only
#     git (diff/log/show/status) but never mutates, never runs `gh`, and holds
#     no GitHub token. All state exits through the run dir on the host.
#
# Usage:
#   bin/review-run.sh [<pr>|--pick] [--dry-run]
#   <pr>       PR to review: repo#num, owner/repo#num, or full pull-request URL.
#              Bare repo slug (#num) and bare number default to the default repo.
#   --pick     Select the oldest open PR labeled `factory:needs-review`.
#   --dry-run  Produce run dir + worktree + brief + session log, but NO PR
#              comment, NO label update, NO task transition, NO workspace-root
#              commit. Lifecycle is simulated.
#
# Exit codes:
#   0  Success (report archived + posted, or dry-run completed)
#   1  Failure (partial review archived; task left in-progress; no completion)
#   2  Usage / selection error (bad <pr>, unresolvable slug, missing PRD, etc.)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test seam: REVIEWER_WORKSPACE lets fixture-based tests point the driver at a
# disposable workspace without any real git/gh context.
WORKSPACE="${REVIEWER_WORKSPACE:-$SCRIPT_DIR}"
CONFIG_FILE="$WORKSPACE/config/reviewer.json"

# ─── Config loading ────────────────────────────────────────────────────────
# Pull scalar values from config/reviewer.json with jq; fall back to a
# here-doc default if jq is unavailable (all values mirrored).
if command -v jq >/dev/null 2>&1; then
  cfg() { jq -r "$1" "$CONFIG_FILE"; }
  MODEL="$(cfg '.model')"
  TIMEOUT_SEC="$(cfg '.timeout_sec')"
  RESPAWN_CAP="$(cfg '.respawn_cap')"
  IMAGE="$(cfg '.image')"
  RUNS_ROOT="$(cfg '.runs_root')"
  REVIEWS_ROOT="$(cfg '.reviews_root')"
  LIVENESS_INTERVAL="$(cfg '.liveness_interval_sec')"
  LIVENESS_IDLE="$(cfg '.liveness_idle_sec')"
  CLEANUP_ENABLED="$(cfg '.cleanup_enabled // true')"
  KEEP_WORKTREE="$(cfg '.keep_worktree // true')"
  PONYTAIL_SKILLS_DIR="$(cfg '.ponytail.skills_dir')"
  PONYTAIL_DEFAULT_MODE="$(cfg '.ponytail.default_mode')"
  HOST_SKILLS="$(cfg '.ponytail.host_skills_dir')"
  HOST_SKILLS="${HOST_SKILLS//\$WORKSPACE/$WORKSPACE}"
  HOST_SKILLS="${HOST_SKILLS//\$\{WORKSPACE\}/$WORKSPACE}"
  repo_map_path() { cfg ".repo_map[\"$1\"] // empty"; }
  env_allowed() { jq -r '.env_allowlist[]' "$CONFIG_FILE"; }
else
  MODEL="openrouter/deepseek/deepseek-v4-flash-0731"
  TIMEOUT_SEC=1800
  RESPAWN_CAP=3
  IMAGE="sandbox:latest"
  RUNS_ROOT="$HOME/.factory/runs"
  REVIEWS_ROOT="docs/code-reviews"
  LIVENESS_INTERVAL=15
  LIVENESS_IDLE=300
  CLEANUP_ENABLED=true
  KEEP_WORKTREE=true
  PONYTAIL_SKILLS_DIR="/skills"
  PONYTAIL_DEFAULT_MODE="ultra"
  HOST_SKILLS="$WORKSPACE/opensource/ponytail/skills"
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
    LANGFUSE_SECRET_KEY LANGFUSE_PUBLIC_KEY LANGFUSE_BASE_URL \
    REVIEWER_MODEL PONYTAIL_DEFAULT_MODE; }
fi

RUNS_ROOT="${RUNS_ROOT/#\~/$HOME}"
# Test seams: allow fixture-based tests to point the run root / archive root at
# a disposable workspace (like REVIEWER_WORKSPACE) without touching real home.
RUNS_ROOT="${REVIEWER_RUNS_ROOT:-$RUNS_ROOT}"
REVIEWS_ROOT="${REVIEWER_REVIEWS_ROOT:-$REVIEWS_ROOT}"

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

# Active gh binary (test seam: point REVIEWER_GH_BIN at a mocked gh). Resolved at
# call time so a fixture can set REVIEWER_GH_BIN after the driver is sourced.
gh_call() { "${REVIEWER_GH_BIN:-gh}" "$@"; }

# Active podman binary (test seam: point REVIEWER_PODMAN_BIN at a mocked podman
# so the driver's `main` can be executed end-to-end without a real container).
podman_call() { "${REVIEWER_PODMAN_BIN:-podman}" "$@"; }

# ─── resolve_pr(): <pr> arg → PR_REPO (owner/repo) + PR_NUMBER ────────────
# Accepts: full PR URL, owner/repo#num, repo#num (repo slug or bare name),
#          or a bare number (defaults to the default repo). Also --pick.
resolve_pr() {
  local arg="${1:-}"
  PR_REPO=""
  PR_NUMBER=""
  case "$arg" in
    --pick)
      pick_pr
      return 0
      ;;
    http*)
      if [[ "$arg" =~ https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
        PR_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        PR_NUMBER="${BASH_REMATCH[3]}"
      else
        die "Cannot parse PR URL: '$arg' (expected https://host/<owner>/<repo>/pull/<num>)"
      fi
      ;;
    */*#*)
      PR_REPO="${arg%%#*}"
      PR_NUMBER="${arg##*#}"
      ;;
    *#*)
      # repo slug shorthand (#num): owner defaults to the workspace origin owner
      local bare="${arg%%#*}"
      PR_NUMBER="${arg##*#}"
      PR_REPO="$(qualify_repo "$bare")"
      ;;
    *[0-9]*)
      # bare number → default repo
      PR_NUMBER="${arg//[^0-9]/}"
      PR_REPO="$(default_repo)"
      ;;
    *)
      die "Cannot interpret PR argument '$arg' (expected repo#num, URL, or --pick)"
      ;;
  esac
  [[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || die "Invalid PR number: '$PR_NUMBER'"
  [ -z "$PR_REPO" ] && die "Could not resolve a repo for '$arg'"
  echo "  Resolved PR: $PR_REPO#$PR_NUMBER" >&2
}

# qualify_repo <name>: turn a bare repo name into owner/repo when it isn't already.
qualify_repo() {
  local name="$1"
  if [[ "$name" == *"/"* ]]; then echo "$name"; return 0; fi
  local owner; owner="$(repo_owner)"
  if [ -n "$owner" ]; then echo "$owner/$name"; else echo "$name"; fi
}

# default_repo: the workspace-root origin repo (owner/repo), or an env override.
default_repo() {
  if [ -n "${REVIEWER_DEFAULT_REPO:-}" ]; then echo "$REVIEWER_DEFAULT_REPO"; return 0; fi
  local url
  url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"
  [ -z "$url" ] && { echo ""; return 0; }
  echo "$url" | sed -E 's#.*[:/]([^/:]+)/([^/.]+)(\.git)?#\1/\2#'
}

repo_owner() {
  local r; r="$(default_repo)"
  echo "${r%%/*}"
}

# pick_pr: oldest open PR labeled factory:needs-review in the default repo.
pick_pr() {
  local repo; repo="${REVIEWER_DEFAULT_REPO:-$(default_repo)}"
  [ -z "$repo" ] && die "--pick needs a default repo (set REVIEWER_DEFAULT_REPO)"
  PR_REPO="$repo"
  local json
  json="$(gh_call pr list --repo "$repo" --label factory:needs-review --state open \
      --json number,title,headRefName --limit 100 2>/dev/null || true)"
  # Oldest open = lowest number.
  PR_NUMBER="$(python3 - "$json" <<'PYEOF'
import json, sys
try:
    data = json.loads(sys.argv[1] or '[]')
except Exception:
    data = []
nums = [int(p.get("number", 0)) for p in data if p.get("number")]
print(min(nums) if nums else "")
PYEOF
  )"
  [ -z "$PR_NUMBER" ] && die "No open PR labeled 'factory:needs-review' in $repo"
  echo "  --pick selected oldest needs-review PR: $repo#$PR_NUMBER" >&2
}

# pr_metadata(): fetch PR title/branch/shas via gh into PR_TITLE, PR_HEAD_REF,
# PR_BASE_REF, PR_HEAD_SHA, PR_BASE_SHA.
pr_metadata() {
  local json
  json="$(gh_call pr view "$PR_NUMBER" --repo "$PR_REPO" --json \
      number,title,headRefName,baseRefName,headRefOid 2>/dev/null || true)"
  if [ -z "$json" ]; then
    die "gh could not fetch PR $PR_REPO#$PR_NUMBER (is gh authenticated on the host?)"
  fi
  PR_TITLE="$(python3 - "$json" <<'PYEOF'
import json, sys
try: d = json.loads(sys.argv[1])
except Exception: d = {}
print(d.get("title", ""))
PYEOF
  )"
  PR_HEAD_REF="$(python3 - "$json" <<'PYEOF'
import json, sys
try: d = json.loads(sys.argv[1])
except Exception: d = {}
print(d.get("headRefName", ""))
PYEOF
  )"
  PR_BASE_REF="$(python3 - "$json" <<'PYEOF'
import json, sys
try: d = json.loads(sys.argv[1])
except Exception: d = {}
print(d.get("baseRefName", ""))
PYEOF
  )"
  PR_HEAD_SHA="$(python3 - "$json" <<'PYEOF'
import json, sys
try: d = json.loads(sys.argv[1])
except Exception: d = {}
print(d.get("headRefOid", ""))
PYEOF
  )"
  PR_BASE_SHA="$(gh_call api "repos/$PR_REPO/pulls/$PR_NUMBER" --jq '.base.sha' 2>/dev/null || true)"
  if [ -z "$PR_BASE_SHA" ]; then
    die "gh could not fetch base SHA for PR $PR_REPO#$PR_NUMBER"
  fi
  echo "  PR #$PR_NUMBER title='$PR_TITLE' head=$PR_HEAD_REF base=$PR_BASE_REF" >&2
}

# ─── resolve_slug(): task slug from PR title or branch ─────────────────────
# Title: "[factory] <slug>: …"  ·  Branch: "factory/<slug>/<ts>"
resolve_slug() {
  local title="${1:-}" branch="${2:-}"
  PRD_SLUG=""
  if [[ "$title" =~ ^\[factory\][[:space:]]*([^:]+): ]]; then
    PRD_SLUG="${BASH_REMATCH[1]}"
  fi
  if [ -z "$PRD_SLUG" ] && [[ "$branch" =~ ^factory/([^/]+)/ ]]; then
    PRD_SLUG="${BASH_REMATCH[1]}"
  fi
  PRD_SLUG="$(echo "$PRD_SLUG" | tr -d '[:space:]')"
  if [ -z "$PRD_SLUG" ]; then
    die "Could not resolve a task slug from PR title '$title' or branch '$branch'."
  fi
  echo "  Resolved task slug: $PRD_SLUG" >&2
}

# ─── resolve_repo(): slug.Project → local repo path via repo_map + PRD ─────
resolve_repo() {
  local task_file="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
  [ -f "$task_file" ] || die "Task file not found: $task_file (slug: $PRD_SLUG)"
  PROJECT="$(grep -m1 '^\*\*Project\*\*:' "$task_file" | sed 's/^\*\*Project\*\*: *//')"
  [ -z "$PROJECT" ] && PROJECT="software-factory"
  TARGET_REPO="$(repo_map_path "$PROJECT")"
  [ -z "$TARGET_REPO" ] && TARGET_REPO="."
  echo "  Resolved project '$PROJECT' → repo '$TARGET_REPO'" >&2

  # The PRD that the PR must be reviewed against.
  PRD="$(ls "$WORKSPACE"/docs/prd-queue/*-"$PRD_SLUG.md" 2>/dev/null | head -1 || true)"
  if [ -z "$PRD" ] || [ ! -f "$PRD" ]; then
    die "No PRD found for slug '$PRD_SLUG' in docs/prd-queue/"
  fi
  echo "  PRD: $(basename "$PRD")" >&2

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

# ─── prepare_run_dir(): worktree (PR head) + outbox + brief ────────────────
# Worktree = PR head. The driver clones the repo, fetches the base ref, checks
# out the PR head, and points origin at the real remote — so the worker can
# `git diff base...head` read-only against a full local git object base.
prepare_run_dir() {
  local ts; ts="$(now_ts)"
  REVIEW_UUID="$(new_uuid)"
  RUN_DIR="$RUNS_ROOT/$PRD_SLUG-$ts"
  WORKTREE="$RUN_DIR/worktree"
  OUTBOX="$RUN_DIR/outbox"
  SESSION_LOG="$RUN_DIR/session.jsonl"
  WORKTREE="$RUN_DIR/worktree"
  mkdir -p "$OUTBOX/decisions" "$RUN_DIR/sessions"
  echo "  Run dir: $RUN_DIR" >&2
  echo "  Review session UUID: $REVIEW_UUID" >&2

  local src_repo="$WORKSPACE/$TARGET_REPO"
  [ -d "$src_repo/.git" ] || die "Target repo not a git repo: $src_repo"

  # Self-contained clone in the run dir (keeps all git metadata writable).
  git clone --quiet --local "$src_repo" "$WORKTREE" 2>/dev/null \
    || git clone --quiet "$src_repo" "$WORKTREE"
  # Point origin at the REAL remote (clone --local sets it to the local path).
  local real_url
  real_url="$(git -C "$src_repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$real_url" ]; then
    git -C "$WORKTREE" remote set-url origin "$real_url"
  fi

  # Fetch base + head so the worker can diff base...head read-only. Prefer the
  # resolved SHAs; fall back to the ref names. The source clone may already hold
  # them (fetch is cheap/local when the objects are present).
  local use_head="${PR_HEAD_SHA:-$PR_HEAD_REF}"
  local use_base="${PR_BASE_SHA:-$PR_BASE_REF}"
  git -C "$WORKTREE" fetch --quiet origin "$use_head" 2>/dev/null \
    || git -C "$WORKTREE" fetch --quiet origin "$use_base" >/dev/null 2>&1 \
    || true
  git -C "$WORKTREE" fetch --quiet origin "$use_base" 2>/dev/null || true
  # Check out the PR head read-only for the reviewer.
  git -C "$WORKTREE" checkout -q "$use_head" 2>/dev/null \
    || git -C "$WORKTREE" checkout -q FETCH_HEAD || true
  echo "  Worktree = PR head: $WORKTREE" >&2

  # No git identity needed here — the reviewer never commits (read-only).

  # Build the verification-commands hint from the PRD's Testing decisions.
  local verify_hint="See the PRD '## Testing decisions' for the acceptance commands. Run them inside the worktree as the PRD specifies; record exactly what runs and what is deferred."

  write_brief "$verify_hint"
}

write_brief() {
  cat > "$RUN_DIR/brief.md" <<EOF
# Code Review Task Brief

- **PR URL**: $PR_REPO#$PR_NUMBER
- **Task slug**: $PRD_SLUG
- **PRD path** (read-only; also below): ${PRD#/workspace/}
- **Review session UUID**: $REVIEW_UUID
- **Worktree path** (PR head, read-only for you): /sandbox/worktree
- **Base ref**: ${PR_BASE_SHA:-$PR_BASE_REF}
- **Head ref**: ${PR_HEAD_SHA:-$PR_HEAD_REF}
- **Outbox path** (write the review report here): /sandbox/outbox

## Rules (binding)

1. You are the READ-ONLY reviewer. You never write to the target repo, never
   commit, and never mutate git state in /sandbox/worktree.
2. Read-only git IS allowed (git diff/log/show/status) — you need it to review
   base...head — but never add/commit/push/checkout/reset/stash.
3. NEVER run 'gh'. Every GitHub call is driver-side. No GitHub credential
   exists in this container.
4. Do NOT modify docs/tasks/, docs/tasks.txt, docs/prd-queue/, or the knowledge
   index. Do NOT write secrets anywhere.
5. Follow the review-ops skill for the check classes + report schema.

## Verification

$1
- State evidence for each check/story (what you ran and how it passed/failed).

## Completion

Write /sandbox/outbox/report.md (per-story + per-check PASS/FAIL with evidence,
blocking vs advisory findings, verdict APPROVE|REQUEST_CHANGES, UAT hand-off
list) and any emerged decisions to /sandbox/outbox/decisions/NN-<slug>.md, then
exit 0. On partial review, still write the report and exit 1.
EOF
  echo "  Brief written: $RUN_DIR/brief.md" >&2
}

# ─── transition(): lifecycle transition (simulated under --dry-run) ────────
# A successful review moves the task in-progress → in-review with the review
# session link. The PRD STAYS in the queue (UAT + user go-ahead come later).
transition() {
  local to="$1"; shift
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would transition $PRD_SLUG → $to (--session $REVIEW_UUID:review)" >&2
    return 0
  fi
  "$WORKSPACE/bin/transition-task.sh" "$PRD_SLUG" --to "$to" \
    --session "$REVIEW_UUID:review" "$@"
}

# ─── Write review session header ───────────────────────────────────────────
write_session_header() {
  mkdir -p "$WORKSPACE/docs/knowledge/sessions/$REVIEW_UUID"
  if [ ! -f "$WORKSPACE/docs/knowledge/sessions/$REVIEW_UUID/session.jsonl" ]; then
    {
      printf '{"type":"session","uuid":"%s","task":"%s","project":"%s","driver":"review-run.sh","start":"%s"}\n' \
        "$REVIEW_UUID" "$PRD_SLUG" "$PROJECT" "$(now_human)"
    } > "$WORKSPACE/docs/knowledge/sessions/$REVIEW_UUID/session.jsonl"
  fi
  echo "  Session log: docs/knowledge/sessions/$REVIEW_UUID/session.jsonl" >&2
}

# ─── Build filtered env-file (no GitHub tokens ever) ───────────────────────
write_env_file() {
  local envfile="$RUN_DIR/secrets.env"
  : > "$envfile"
  chmod 600 "$envfile"
  local name
  while read -r name; do
    [ -z "$name" ] && continue
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [ -n "${!name:-}" ]; then
      printf '%s=%s\n' "$name" "${!name}" >> "$envfile"
    fi
  done < <(env_allowed)
  # Force the ponytail default mode into the container (config-driven).
  if [ -n "$PONYTAIL_DEFAULT_MODE" ]; then
    printf 'PONYTAIL_DEFAULT_MODE=%s\n' "$PONYTAIL_DEFAULT_MODE" >> "$envfile"
  fi
  # ── LLM credential fallback from pi's auth.json (the same file pi reads) ──
  # For allowlisted provider env vars left unset by the host env, resolve the
  # key from ~/.pi/agent/auth.json. Scoped strictly to the allowlist mapping —
  # the github-copilot access token and the nvidia key never enter the
  # container. Values go straight to the envfile, never echoed.
  local auth_file="${PI_AUTH_FILE:-$HOME/.pi/agent/auth.json}"
  if [ -f "$auth_file" ]; then
    local name provider key
    while read -r name; do
      [ -z "$name" ] && continue
      case "$name" in
        OPENROUTER_API_KEY) provider=openrouter ;;
        ANTHROPIC_API_KEY)  provider=anthropic ;;
        *) continue ;;
      esac
      if ! grep -q "^${name}=" "$envfile"; then
        key="$(python3 -c '
import json, sys
provider, auth_file = sys.argv[1], sys.argv[2]
try:
    with open(auth_file) as f:
        auth = json.load(f)
    sys.stdout.write(auth.get(provider, {}).get("key", ""))
except Exception:
    sys.exit(1)
' "$provider" "$auth_file")" || continue
        if [ -n "$key" ]; then
          printf '%s=%s\n' "$name" "$key" >> "$envfile"
        fi
      fi
    done < <(env_allowed)
  fi
  echo "$envfile"
}

# ─── ponytail_skill_flags(): the six review `--skill` flags (Decision 04) ──
# Testable seam + used by run_container. The skills are bind-mounted read-only
# at the fixed container path /skills (not inherited from a host checkout);
# reviewer-scoped, never touches shared .pi/settings.json.
PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help)
ponytail_skill_flags() {
  local s
  for s in "${PONYTAIL_SKILL_NAMES[@]}"; do
    printf '%s\n' "--skill $PONYTAIL_SKILLS_DIR/$s"
  done
}

# ─── run_container(): one podman attempt, streamed live ────────────────────
# Returns 0 on reviewer success (report present), 1 on container/review failure.
run_container() {
  local attempt="$1"
  local envfile; envfile="$(write_env_file)"

  local model_arg=()
  if [ -n "${REVIEWER_MODEL:-}" ]; then
    model_arg=(--model "$REVIEWER_MODEL")
  elif [ -n "${MODEL:-}" ] && [ "$MODEL" != "null" ]; then
    model_arg=(--model "$MODEL")
  elif [ -n "${PI_MODEL:-}" ]; then
    model_arg=(--model "${PI_PROVIDER:-openrouter}/${PI_MODEL}")
  fi

  # The six ponytail skills, bind-mounted read-only from the host skills
  # checkout at /skills. If the host checkout is absent, warn loudly and run
  # WITHOUT the flags/mount (ponytail is advisory — never a blocker, never a
  # fabrication incentive; warn-and-run, never silent, never fail-fast).
  local pony=()
  local skills_mount=()
  if [ -d "$HOST_SKILLS" ]; then
    while IFS= read -r flag; do pony+=($flag); done < <(ponytail_skill_flags)
    skills_mount=(-v "$HOST_SKILLS:/skills:ro")
  else
    echo "WARN: ponytail skills not found at ${HOST_SKILLS:-<unset>}; running without ponytail discipline" >&2
  fi

  local container_out="$RUN_DIR/container-$attempt.log"
  echo "  [attempt $attempt/$RESPAWN_CAP] podman run $IMAGE ..." >&2

  local cname="review-$REVIEW_UUID"
  if command -v "${REVIEWER_PODMAN_BIN:-podman}" >/dev/null 2>&1; then
    podman_call rm -f "$cname" >/dev/null 2>&1 || true
  fi

  local sess_args=(--session-dir /sandbox/sessions)
  if [ "$attempt" -gt 1 ]; then
    sess_args+=(--continue)
  fi

  local directive
  if [ "$attempt" -eq 1 ]; then
    directive="Execute your code-review run contract now. Read /sandbox/brief.md and the PRD it references, review the PR in /sandbox/worktree against the PRD (read-only git diff base...head only, never mutate, never run gh), run the PRD verification commands, run the deterministic + judgment checks including the ponytail-review over-engineering pass at ultra, then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  else
    directive="Resume your interrupted code-review run. You were killed mid-run; this container continues the SAME session and the checkout is already on disk in /sandbox/worktree. Continue from where you left off — do NOT restart from scratch. Finish the review per /sandbox/brief.md (read-only git only, never mutate, never run gh), then write /sandbox/outbox/report.md plus any decisions to /sandbox/outbox/decisions/. Exit 0 on success."
  fi

  local exit_code=0
  (
    # NOTE: no `exec` here — podman_call is a function seam, not an external
    # command, so the subshell simply runs it and exits when it returns.
    podman_call run --rm --network=host \
      --name "review-$REVIEW_UUID" \
      -v "$WORKSPACE:/workspace:ro" \
      "${skills_mount[@]}" \
      -v "$RUN_DIR:/sandbox" \
      --env-file "$envfile" \
      "$IMAGE" \
      pi --mode json -p \
        "${sess_args[@]}" \
        "${pony[@]}" \
        --append-system-prompt /sandbox/brief.md \
        --append-system-prompt /workspace/.pi/agents/code-reviewer.md \
        "${model_arg[@]}" \
        "$directive"
  ) > "$container_out" 2>&1 & local pid=$!

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
    if [ -f "$container_out" ]; then
      local size; size=$(wc -c < "$container_out")
      if [ "$size" -gt "$last_size" ]; then
        local slice; slice=$(tail -c +$((last_size+1)) "$container_out")
        printf '%s' "$slice" >> "$SESSION_LOG"
        local s; s=$(printf '%s' "$slice" | grep -c '"type":"tool_execution_start"' || true)
        local e; e=$(printf '%s' "$slice" | grep -c '"type":"tool_execution_end"' || true)
        tool_open=$((tool_open + s - e)); [ "$tool_open" -lt 0 ] && tool_open=0
        last_size="$size"
        last_activity=$(date +%s)
      fi
    fi
    if [ "$tool_open" -eq 0 ] && [ "$last_activity" -ne 0 ] && [ $(( $(date +%s) - last_activity )) -gt "$LIVENESS_IDLE" ]; then
      echo "  [liveness] no output for ${LIVENESS_IDLE}s (no tool running) — treating as stuck." >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep "$LIVENESS_INTERVAL"
  done
  wait "$pid" || exit_code=$?

  if [ -f "$container_out" ]; then
    local size; size=$(wc -c < "$container_out")
    if [ "$size" -gt "$last_size" ]; then
      tail -c +$((last_size+1)) "$container_out" >> "$SESSION_LOG"
    fi
  fi

  if [ -f "$OUTBOX/report.md" ]; then
    echo "  [attempt $attempt] reviewer completed with report; exit=$exit_code" >&2
    return 0
  fi
  echo "  [attempt $attempt] reviewer did not complete; exit=$exit_code" >&2
  return 1
}

# ─── archive(): copy outbox → docs/code-reviews/<date>-<slug>/ ─────────────
archive() {
  local ts; ts="$(date '+%Y-%m-%d')"
  local dest="$WORKSPACE/$REVIEWS_ROOT/$ts-$PRD_SLUG"
  mkdir -p "$dest/decisions"
  if [ -f "$OUTBOX/report.md" ]; then
    cp "$OUTBOX/report.md" "$dest/report.md"
  fi
  if [ -d "$OUTBOX/decisions" ]; then
    cp "$OUTBOX/decisions/"*.md "$dest/decisions/" 2>/dev/null || true
  fi
  cp "$RUN_DIR/brief.md" "$dest/brief.md"
  echo "  Archived review artifacts → $dest" >&2
  ARCHIVE_DEST="$dest"
}

# ─── post_pr_comment(): gh pr comment (host-side, no token in container) ───
post_pr_comment() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would post review to $PR_REPO#$PR_NUMBER via gh pr comment" >&2
    return 0
  fi
  if ! command -v "${REVIEWER_GH_BIN:-gh}" >/dev/null 2>&1; then
    echo "  [warn] gh not available; review archived but PR comment skipped." >&2
    return 1
  fi
  local body_file="$RUN_DIR/review-comment.md"
  {
    echo "## Code Review ($PRD_SLUG)"
    echo ""
    if [ -f "$ARCHIVE_DEST/report.md" ]; then cat "$ARCHIVE_DEST/report.md"; fi
  } > "$body_file"
  gh_call pr comment "$PR_NUMBER" --repo "$PR_REPO" --body-file "$body_file"
  echo "  Posted review comment to $PR_REPO#$PR_NUMBER." >&2
}

# ─── update_label(): tag the PR with the outcome (host-side) ───────────────
update_label() {
  local outcome="$1"  # reviewed-ok | review-blocked
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would label $PR_REPO#$PR_NUMBER → factory:$outcome" >&2
    return 0
  fi
  # Ensure the label family exists once; the driver makes --label idempotent.
  gh_call label create "factory:$outcome" --repo "$PR_REPO" --force >/dev/null 2>&1 || true
  # REST label endpoints: `gh pr edit --add-label/--remove-label` fails on some
  # accounts with the classic-Projects-deprecation GraphQL error and silently
  # no-ops under `|| true` (see decision 07-label-seam-gh-pr-edit). Use the
  # issue-labels REST API which bypasses projectCards.
  gh_call api -X POST "repos/$PR_REPO/issues/$PR_NUMBER/labels" \
    -f "labels[]=factory:$outcome" >/dev/null 2>&1 || true
  gh_call api -X DELETE "repos/$PR_REPO/issues/$PR_NUMBER/labels/factory:needs-review" \
    --silent >/dev/null 2>&1 || true
  echo "  Labeled $PR_REPO#$PR_NUMBER → factory:$outcome." >&2
}

# ─── stop_container(): ensure the run's sandbox container is shut down ─────
stop_container() {
  local cname="review-$REVIEW_UUID"
  if command -v "${REVIEWER_PODMAN_BIN:-podman}" >/dev/null 2>&1 \
      && podman_call ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
    echo "  Shutting down sandbox container $cname (no longer needed)." >&2
    podman_call stop -t 5 "$cname" >/dev/null 2>&1 || true
    podman_call rm -f "$cname" >/dev/null 2>&1 || true
  fi
}

# ─── cleanup_run_dir(): dispose the throwaway residue after a run ──────────
cleanup_run_dir() {
  local keep_logs=false
  [ "${1:-}" = "--keep-logs" ] && keep_logs=true
  local deps=0
  if [ -d "$WORKTREE" ]; then
    while IFS= read -r -d '' d; do
      rm -rf "$d" && deps=$((deps+1))
    done < <(find "$WORKTREE" -type d \( -name node_modules -o -name 'venv*' \
      -o -name .venv -o -name __pycache__ -o -name .pytest_cache \) \
      -prune -print0 2>/dev/null || true)
  fi
  if [ "$keep_logs" = false ]; then
    rm -f "$RUN_DIR"/container-*.log "$RUN_DIR"/session.jsonl
  fi
  rm -f "$RUN_DIR"/secrets.env
  if [ "$KEEP_WORKTREE" = "0" ] && [ -d "$WORKTREE" ]; then
    rm -rf "$WORKTREE"
  fi
  echo "  Cleanup: removed $deps disposable dep dirs + raw trace from $RUN_DIR (durable artifacts kept)." >&2
}

# ─── failure path ──────────────────────────────────────────────────────────
fail_run() {
  local reason="$1"
  echo "  FAILED: $reason" >&2
  stop_container
  if [ "$DRY_RUN" != true ] && [ "${REVIEW_CLEANUP:-$CLEANUP_ENABLED}" != "false" ]; then
    cleanup_run_dir --keep-logs
  fi
  if [ -d "$OUTBOX" ] && [ -f "$OUTBOX/report.md" ]; then
    archive
  elif [ -d "$OUTBOX" ]; then
    cp "$RUN_DIR/brief.md" "$OUTBOX/partial-report.md" 2>/dev/null || true
    echo "# Partial review" > "$OUTBOX/report.md"
    echo "" >> "$OUTBOX/report.md"
    echo "Run failed: $reason" >> "$OUTBOX/report.md"
    archive
  fi
  # Task stays in-progress on a partial review (no completion transition).
  exit 1
}

# ─── finalize_session_copy(): persist the streamed transcript ──────────────
finalize_session_copy() {
  local sess="$WORKSPACE/docs/knowledge/sessions/$REVIEW_UUID/session.jsonl"
  local native=""
  if compgen -G "$RUN_DIR/sessions/*.jsonl" >/dev/null 2>&1; then
    native="$(ls -t "$RUN_DIR"/sessions/*.jsonl 2>/dev/null | head -1)"
  fi
  if [ -n "$native" ] && [ -s "$native" ]; then
    cp "$native" "$sess"
  elif [ -s "$SESSION_LOG" ]; then
    cp "$SESSION_LOG" "$sess"
  fi
  # GH013 guard: this transcript is committed to the repo (tracking commit).
  # Sanitize the committed copy IN-PLACE so GitHub push protection never
  # blocks it; the RAW native session stays in RUN_DIR/sessions/ for the
  # private trace bundle. If sanitize is incomplete, warn — never abort.
  if [ -s "$sess" ]; then
    if bash "$WORKSPACE/bin/sanitize-session.sh" "$sess" >/dev/null 2>&1; then
      :
    else
      echo "  WARN: session sanitize incomplete (rc=$?) — add patterns to bin/sanitize-session.sh" >&2
    fi
  fi
}

# ─── main ──────────────────────────────────────────────────────────────────
if [ "${REVIEWER_RUN_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

echo "=== review-run.sh ==="
DRY_RUN=false
echo "  dry-run: $DRY_RUN | target: ${PR_UNSET:-unspecified}"

# ─── Arg parsing ───────────────────────────────────────────────────────────
PR_ARG=""
PICK_MODE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --pick) PICK_MODE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --*) die "Unknown option: $1" ;;
    *) PR_ARG="$1"; shift ;;
  esac
done

if [ "$PICK_MODE" = true ]; then
  PR_ARG="--pick"
fi
[ -z "$PR_ARG" ] && { echo "Usage: bin/review-run.sh <pr>|--pick [--dry-run]"; exit 2; }

echo "  dry-run: $DRY_RUN | target: $PR_ARG"

# Resolve which PR, which slug, which repo/PRD.
resolve_pr "$PR_ARG"
pr_metadata
resolve_slug "$PR_TITLE" "$PR_HEAD_REF"
resolve_repo

prepare_run_dir
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
finalize_session_copy

if [ "$local_result" -eq 0 ]; then
  echo "=== Review success — archiving + delivering ===" >&2
  archive
  # Determine verdict from the report (driver-side decision, for label + gate).
  verdict="$(grep -m1 '^APPROVE\|^REQUEST_CHANGES' "$OUTBOX/report.md" 2>/dev/null \
    | tr -d '[:space:]' || true)"
  case "$verdict" in
    APPROVE*) REVIEW_OUTCOME="reviewed-ok" ;;
    REQUEST_CHANGES*) REVIEW_OUTCOME="review-blocked" ;;
    *) REVIEW_OUTCOME="reviewed-ok" ;;
  esac
  # AUTHORITY SPLIT: the reviewer NEVER merges. Merge is the user/operator's
  # go-ahead action after UAT (decision 05-review-never-merges). This driver
  # has no merge path by design — APPROVE only labels + transitions to in-review.
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would post comment, label factory:$REVIEW_OUTCOME, and transition to in-review" >&2
  else
    post_pr_comment || true
    update_label "$REVIEW_OUTCOME"
    # Decision 06: attach the review row to the task file (rides the commit
    # below). No `local` here — this is top-level scope.
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/bin/lib-pr-tracking.sh" 2>/dev/null || true
    task_file="$WORKSPACE/docs/tasks/$PRD_SLUG.md"
    if pr_tracking_ensure "$task_file"; then
      report_rel="$REVIEWS_ROOT/$(date '+%Y-%m-%d')-$PRD_SLUG"
      if ! pr_tracking_has "$task_file" "Review: session $REVIEW_UUID"; then
        pr_tracking_add "$task_file" \
          "- Review: session $REVIEW_UUID · verdict ${verdict:-n/a} · report $report_rel/"
      fi
    fi
    # Successful review → task in-progress → in-review with the review session.
    transition "in-review"
    ( cd "$WORKSPACE" && git add "$REVIEWS_ROOT" docs/knowledge/sessions/$REVIEW_UUID \
        docs/tasks/$PRD_SLUG.md docs/tasks.txt 2>/dev/null || true
      git diff --cached --quiet || git commit -m "reviewer($PRD_SLUG): archive review report + decisions [review $REVIEW_UUID]" )
  fi
  stop_container
  if [ "$DRY_RUN" != true ] && [ "${REVIEW_CLEANUP:-$CLEANUP_ENABLED}" != "false" ]; then
    cleanup_run_dir
  fi
  echo "Done (exit 0)."
  exit 0
else
  fail_run "container/reviewer failed after ${RESPAWN_CAP} attempts"
fi
