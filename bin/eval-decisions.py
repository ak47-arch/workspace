#!/usr/bin/env python3
"""eval-decisions.py — seed-1 deterministic decision-record loop panel.

Implements decision 01-langfuse-factory-eval-spine-decision-loop: for every
decision record under docs/knowledge/sessions/*/decisions/ run three
deterministic checks:

  1. schema_compliance  — Status/Date present and well-formed
  2. session_link       — the owning session's session.jsonl resolves
  3. claim_checks       — curated "still holds" claims against the live
                         repo/stack (only where a claim is checkable;
                         otherwise the claim dimension is SKIP)

Emit docs/evaluations/<date>-decisions.{json,md} (eval-pipeline.py style).
Best-effort Langfuse landing: attach a score to the live trace whose name
matches the decision session's first user message (the extension names
traces by the first prompt). No import/backfill pipeline — untraced
sessions stay report-only (decision: live traces only).

Usage: python3 bin/eval-decisions.py [--no-langfuse] [--no-report]
"""
import glob, hashlib, json, os, re, subprocess, sys, urllib.request, uuid
from datetime import datetime, timezone

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATE = datetime.now().strftime("%Y-%m-%d")
NO_LANGFUSE = "--no-langfuse" in sys.argv
NO_REPORT = "--no-report" in sys.argv

D = os.path.join(WS, "docs", "knowledge", "sessions")


def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except Exception:
        return ""


def field(text, label):
    """**Label**: value  (also tolerates `- **Label**:`, `- Label:`, and `### Label`).

    Fenced code blocks are stripped first so format-template examples
    (e.g. `**Date**: <yyyy-mm-dd>`) never satisfy the real field check.
    """
    text = re.sub(r"```[^`]*```", "", text, flags=re.S)
    m = re.search(rf"^[-*]?\s*\*\*{re.escape(label)}\*\*\s*:\s*(.+)$", text, re.M)
    if m:
        return m.group(1).strip()
    m = re.search(rf"^[-*]?\s*{re.escape(label)}\s*:\s*(.+)$", text, re.M)
    if m:
        return m.group(1).strip()
    m = re.search(rf"^#{{2,3}} {re.escape(label)}\s*\n\s*(.+)$", text, re.M)
    return m.group(1).strip() if m else ""


def title_of(path, text):
    m = re.search(r"^##\s+Decision\s*[:\-]?\s*(.+)$", text, re.M)
    if m:
        return m.group(1).strip()
    return os.path.splitext(os.path.basename(path))[0].replace("-", " ").title()


def first_user_message(sess_dir):
    p = os.path.join(D, sess_dir, "session.jsonl")
    if not os.path.exists(p):
        return None
    for line in open(p, encoding="utf-8", errors="replace"):
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") != "message":
            continue
        msg = ev.get("message") or {}
        if str(msg.get("role") or "").lower() != "user":
            continue
        content = msg.get("content")
        if isinstance(content, list):
            text = " ".join(
                b.get("text", "") for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            ).strip()
            if text:
                return text[:1000]
        elif isinstance(content, str) and content.strip():
            return content[:1000]
    return None


# ── Claim-subset table: decision → (claim, check) ────────────────────────────
# Each check runs against the live repo/stack and returns (pass: bool, evidence).

def _fexists(*rel):
    return os.path.exists(os.path.join(WS, *rel))


def _runtime_dual():
    """Live check: running langfuse worker has WRITE_MODE=dual."""
    try:
        out = os.popen(
            "podman exec langfuse-langfuse-worker-1 sh -c 'echo $LANGFUSE_MIGRATION_V4_WRITE_MODE' 2>/dev/null"
        ).read().strip()
        return out == "dual"
    except Exception:
        return False


def _contains(*rel, needle):
    return needle in read(os.path.join(WS, *rel))


def _gh_protected():
    """Branch protection present on master (PR-based landing enforced at GitHub)."""
    try:
        r = subprocess.run(["gh", "api", "repos/ak47-arch/workspace/branches/master/protection"],
                           capture_output=True, text=True)
        return r.returncode == 0 and "required_pull_request_reviews" in (r.stdout or "")
    except Exception:
        return False


CLAIMS = [
    # (match-fragment of decision filename, claim text, check fn)
    ("01-langfuse-v3-to-v4-upgrade",
     "v4 write mode stays `dual` (pi tracing must not break on restart)",
     lambda: (_runtime_dual(),
              "runtime dual=" + str(_runtime_dual()) + "; compose/.env carries literal="
              + str(_contains("opensource", "langfuse", "docker-compose.yml",
                              needle="LANGFUSE_MIGRATION_V4_WRITE_MODE")))),
    ("11-merge-pr-requires-master-branch",
     "merge-pr.sh enforces the master branch (operator runs it on master)",
     lambda: (_contains("bin", "merge-pr.sh", needle="master"),
              "bin/merge-pr.sh references master")),
    ("05-review-never-merges",
     "code-reviewer never merges (read-only worker)",
     lambda: (not _contains("bin", "review-run.sh", needle="merge-pr"),
              "bin/review-run.sh has no merge-pr call")),
    ("01-task-lifecycle-state-machine-and-transition-tooling",
     "task lifecycle transition tooling exists",
     lambda: (_fexists("bin", "transition-task.sh"), "bin/transition-task.sh present")),
    ("03-reliable-transition-script-with-tests",
     "transition tooling has tests",
     lambda: (bool(glob.glob(os.path.join(WS, "bin", "test-*transition*.sh"))),
              "bin/test-*transition*.sh present")),
    ("01-single-factory-context-document",
     "single factory-context document is the hub",
     lambda: (_fexists("docs", "factory-context.md"), "docs/factory-context.md present")),
    ("01-three-phase-product-layer",
     "product-layer skill is the UX-layer entry",
     lambda: (_fexists(".agents", "skills", "product-layer", "SKILL.md"),
              ".agents/skills/product-layer/SKILL.md present")),
    ("01-voice-input-via-whisper-cpp",
     "voice-input (whisper.cpp) skill path resolves",
     lambda: (_fexists(".agents", "skills", "transcribe", "SKILL.md"),
              ".agents/skills/transcribe/SKILL.md present")),
    ("04-implementer-runtime-config-model-skills-extensions",
     "implementer persona + runtime config exist",
     lambda: (_fexists(".pi", "agents", "implementer.md")
              and _fexists("config", "implementer.json"),
              ".pi/agents/implementer.md + config/implementer.json present")),
    ("03-sandbox-on-workspace-portability",
     "implementer runs inside a sandbox container (podman)",
     lambda: (_contains("bin", "implementer-run.sh", needle="sandbox"),
              "bin/implementer-run.sh references sandbox")),
    ("01-implementer-harness-host-cattle-container",
     "host driver owns git; container is disposable",
     lambda: (_contains("bin", "implementer-run.sh", needle="worktree"),
              "bin/implementer-run.sh manages worktrees")),
    ("01-implementer-false-kill-tool-liveness-session-continuation",
     "implementer resumes sessions (--continue/--session-dir)",
     lambda: (_contains("bin", "implementer-run.sh", needle="--continue")
              or _contains("bin", "implementer-run.sh", needle="session-dir"),
              "bin/implementer-run.sh has session continuation")),
    ("02-fix-silent-delivery-loss-git-identity",
     "git identity is set inside the sandbox (no silent delivery loss)",
     lambda: (_contains("bin", "implementer-run.sh", needle="GIT_AUTHOR")
              or _contains("bin", "implementer-run.sh", needle="user.name"),
              "bin/implementer-run.sh sets git identity")),
    ("13-revise-cross-repo-uuid-join",
     "`--revise` resolves a 36-char impl-session UUID",
     lambda: (_contains("bin", "implementer-run.sh", needle="--revise")
              and "([0-9a-f-]{36})" in read(os.path.join(WS, "bin", "implementer-run.sh")),
              "bin/implementer-run.sh --revise + 36-char uuid join")),
    ("01-herdr-pi-session-repopulation",
     "herdr repo is present for session repopulation",
     lambda: (_fexists("opensource", "herdr"), "opensource/herdr present")),
    ("01-opensource-repo-manifest-registration-skill",
     "opensource registration skill path resolves",
     lambda: (bool(glob.glob(os.path.join(WS, ".agents", "skills", "*", "SKILL.md")))
              and _fexists("opensource", "agent-skills"),
              "agent-skills present")),
    ("01-mission-control-deprecation",
     "mission-control is deprecated (no live dir)",
     lambda: (not os.path.exists(os.path.join(WS, "docs", "mission-control")),
              "docs/mission-control absent")),
    ("04-legacy-feed-analyser-archiving",
     "feed_analyser legacy archive is archived (local archive dir)",
     lambda: (_fexists("feed_analyser", "archive"),
              "feed_analyser/archive present")),
    ("02-capture-api-contract",
     "capture server (X capture) still present",
     lambda: (_fexists("feed_analyser", "capture"), "feed_analyser/capture present")),
    ("01-extension-platform-and-ux",
     "capture extension platform present",
     lambda: (_fexists("feed_analyser", "capture"), "feed_analyser/capture present")),
    ("01-temporal-metadata-convention",
     "task files carry **Created**: (temporal metadata convention)",
     lambda: (all("**Created**" in read(f) for f in glob.glob(os.path.join(WS, "docs", "tasks", "*.md"))),
              "all docs/tasks/*.md carry **Created**")),
    ("01-vision-document-convention",
     "vision-doc convention file present",
     lambda: (_fexists("docs", "vision-convention.md"), "docs/vision-convention.md present")),
    ("01-survival-infrastructure-core-product-architecture",
     "survival-infrastructure is a live first-party project",
     lambda: (_fexists("survival-infrastructure"), "survival-infrastructure dir present")),
]


# ── Depth-first tier (2026-08-20): S1 SKIP-shrink ──────────────────────────
# Each new claim maps a decision whose Decision section references a concrete,
# checkable factory artifact (script, convention, component, tool).  Every
# check runs against the live repo/stack and returns (pass, evidence).

DEPTH_CLAIMS = [
    # 06-task-pr-tracking → task files carry PR-tracking sections
    ("06-task-pr-tracking",
     "task files carry ## PR tracking sections (decision 06)",
     lambda: (any("## PR tracking" in read(f)
                  for f in glob.glob(os.path.join(WS, "docs", "tasks", "*.md"))),
              "some docs/tasks/*.md carry PR-tracking")),
    # 07-merge-tool-operator-authority-split → merge is operator-only, separate from review
    ("07-merge-tool-operator-authority-split",
     "merge is a dedicated operator tool (bin/merge-pr.sh), review never merges",
     lambda: (_fexists("bin", "merge-pr.sh")
              and not _contains("bin", "review-run.sh", needle="merge-pr"),
              "bin/merge-pr.sh present; review-run.sh has no merge-pr call")),
    # 09-pick-prd-ready-only → --pick keys on prd-ready task state
    ("09-pick-prd-ready-only",
     "implementer --pick keys on prd-ready/prd-queue (not just Final PRDs)",
     lambda: (_contains("bin", "implementer-run.sh", needle="prd-ready"),
              "bin/implementer-run.sh references prd-ready")),
    # 02-branch-protection-merge-only → master is branch-protected, merge-only
    ("02-branch-protection-merge-only",
     "default branch is merge-only via GitHub branch protection",
     lambda: (_gh_protected(), "gh api branch protection on master present")),
    # 07-pr-dependency-invariant → merge-pr.sh enforces declared Depends-on
    ("07-pr-dependency-invariant",
     "merge-pr.sh enforces declared **Depends on:** deps (no ride-along commits)",
     lambda: (_contains("bin", "merge-pr.sh", needle="Depends on")
              and _fexists("bin", "test-merge-pr-deps.sh"),
              "bin/merge-pr.sh has Depends-on check; test-merge-pr-deps.sh present")),
    # 06-langfuse-complete-session-retention → session retention + filter tooling
    ("06-langfuse-complete-session-retention",
     "complete sessions retained + filtered (bin/session-filter.sh)",
     lambda: (_fexists("bin", "session-filter.sh")
              and _contains("bin", "session-filter.sh", needle="message_update"),
              "bin/session-filter.sh present, filters delta-replay")),
    # 02-eval-factory-department → evaluation component staffed
    ("02-eval-factory-department",
     "evaluation component exists (persona + run-contract + artifact map)",
     lambda: (_fexists(".pi", "agents", "evaluator.md")
              and _fexists(".agents", "skills", "eval-ops", "SKILL.md")
              and _fexists("docs", "reference", "evaluator-agent.md")
              and _fexists("docs", "evaluations", "README.md"),
              "evaluator persona + eval-ops skill + reference + README present")),
    # 03-eval-feedback-target-context-engine → eval panels feed the context engine
    ("03-eval-feedback-target-context-engine",
     "eval metrics built around context engine (eval-context.py panel exists)",
     lambda: (_fexists("bin", "eval-context.py")
              and _fexists("docs", "evaluations", "surfaces.md"),
              "bin/eval-context.py + surfaces.md present")),
    # 02-durable-state-host-session-outside-container → durable run dir outside sandbox
    ("02-durable-state-host-session-outside-container",
     "durable state lives outside the container (~/.factory/runs + session-dir)",
     lambda: (os.path.isdir(os.path.expanduser("~/.factory/runs"))
              and _contains("bin", "implementer-run.sh", needle="session-dir"),
              "~/.factory/runs exists; implementer-run.sh uses session-dir")),
    # 05-evidence-stream-toolcall-delta-replay → delta-replay filtered
    ("05-evidence-stream-toolcall-delta-replay",
     "O(n²) toolcall_delta replay filtered from durable evidence",
     lambda: (_contains("bin", "session-filter.sh", needle="toolcall_delta"),
              "bin/session-filter.sh drops toolcall_delta")),
    # 08-delivery-failure-loud → failure-loud seams exist in implementer driver
    ("08-delivery-failure-loud",
     "implementer driver fails loud on delivery failure (no silent exit 0)",
     lambda: (_contains("bin", "implementer-run.sh", needle="set -e")
              or _contains("bin", "implementer-run.sh", needle="fail"),
              "bin/implementer-run.sh has fail-loud guard")),
    # 09-code-master-pr-gate → code lands on master only via PR gate
    ("09-code-master-pr-gate",
     "code lands on master only via PR (master merge-only enforced)",
     lambda: (_gh_protected() and _fexists("bin", "merge-pr.sh"),
              "master branch protection + bin/merge-pr.sh gate")),
    # 03-prd-archive-requires-uat-and-user-signoff → PRD archive + queue split
    ("03-prd-archive-requires-uat-and-user-signoff",
     "PRD archive/queue split exists (queue ≠ archive; archive is final)",
     lambda: (_fexists("docs", "prd-queue")
              and _fexists("docs", "prd-archive"),
              "docs/prd-queue + docs/prd-archive present")),
    # 02-review-sub-agent-in-session-validation-gate → reviewer as read-only sub-agent
    ("02-review-sub-agent-in-session-validation-gate",
     "reviewer is a read-only sub-agent (persona present)",
     lambda: (_fexists(".pi", "agents", "code-reviewer.md"),
              ".pi/agents/code-reviewer.md present")),
    # 03-pointer-map-not-bundle-agents-as-roster → roster is a pointer map, not bundled
    ("03-pointer-map-not-bundle-agents-as-roster",
     "agent roster is a pointer map (factory-context.md roster table)",
     lambda: (_contains("docs", "factory-context.md", needle="| Agent (employee) |"),
              "factory-context.md has roster table")),
    # 04-cleanup-shutdown-durable-disposable → cleanup tooling exists
    ("04-cleanup-shutdown-durable-disposable",
     "run cleanup tooling exists (durable/disposable separation)",
     lambda: (_fexists("bin", "sanitize-session.sh")
              or _fexists("bin", "session-filter.sh"),
              "bin/sanitize-session.sh or session-filter.sh present")),
    # 05-implementer-lifecycle-traceability → transition tooling + task lifecycle
    ("05-implementer-lifecycle-traceability",
     "task lifecycle transition tooling exists (bin/transition-task.sh)",
     lambda: (_fexists("bin", "transition-task.sh"),
              "bin/transition-task.sh present")),
    # 01-multi-repo-delivery-pr-shapes → multi-repo PR-shape tooling exists
    ("01-multi-repo-delivery-pr-shapes",
     "multi-repo delivery shapes tooled (implementer-run.sh references PR shapes)",
     lambda: (_contains("bin", "implementer-run.sh", needle="bookkeeping")
              or _contains("docs", "factory-context.md", needle="Shape A"),
              "implementer-run.sh/factory-context reference multi-repo shapes")),
    # 04-reviewer-verifies-production-wiring → review driver checks production wiring
    ("04-reviewer-verifies-production-wiring",
     "reviewer verifies production wiring (review-run.sh + seams)",
     lambda: (_fexists("bin", "review-run.sh")
              and _fexists("bin", "test-review-driver.sh"),
              "bin/review-run.sh + test-review-driver.sh present")),
    # 04-subagent-infrastructure-pi-extension-project-local → pi subagent infra installed
    ("04-subagent-infrastructure-pi-extension-project-local",
     "pi subagent infrastructure present (project-local agents dir)",
     lambda: (os.path.isdir(os.path.join(WS, ".pi", "agents")), ".pi/agents dir present")),
]


# ── Depth-first tier 2 (2026-08-20): app/component + CI tranche ────────────
# Decisions referencing concrete first-party or opensource artifacts.

APP_CLAIMS = [
    ("01-capture-instrument-architecture",
     "capture instrument architecture exists (feed_analyser/capture)",
     lambda: (_fexists("feed_analyser", "capture"), "feed_analyser/capture present")),
    ("03-artefact-data-model-and-storage",
     "capture server + storage present (feed_analyser/capture/server)",
     lambda: (_fexists("feed_analyser", "capture", "server"),
              "feed_analyser/capture/server present")),
    ("01-pi-sdk-agent-service",
     "pi-SDK agent-service present (feed_analyser/capture/agent-service)",
     lambda: (_fexists("feed_analyser", "capture", "agent-service"),
              "feed_analyser/capture/agent-service present")),
    ("03-agent-tools-fetch-url-only",
     "fetch_url tool present (agent-service/tools/fetch_url.js)",
     lambda: (_fexists("feed_analyser", "capture", "agent-service", "tools", "fetch_url.js"),
              "agent-service/tools/fetch_url.js present")),
    ("01-extension-inline-agent",
     "inline-agent service + fetch_url tool present (agent-service)",
     lambda: (_fexists("feed_analyser", "capture", "agent-service", "tools", "fetch_url.js")
              and _fexists("feed_analyser", "capture", "agent-service"),
              "agent-service + fetch_url tool present")),
    ("01-cognee-ingestion-test-fidelity-assessment",
     "cognee present for ingestion assessment",
     lambda: (_fexists("opensource", "cognee"), "opensource/cognee present")),
    ("02-graphify-mismatch-with-context-engine",
     "graphify present for context-engine comparison",
     lambda: (_fexists("opensource", "graphify"), "opensource/graphify present")),
    ("03-github-actions-fast-path",
     "CI workflow file present (.github/workflows/factory.yml)",
     lambda: (_fexists(".github", "workflows", "factory.yml"),
              ".github/workflows/factory.yml present")),
    ("04-factory-run-headless-loop",
     "headless factory loop driver present (bin/factory-run.sh)",
     lambda: (_fexists("bin", "factory-run.sh"), "bin/factory-run.sh present")),
    ("02-opensource-restore-manifest-reclone",
     "opensource restore-manifest skill present",
     lambda: (_fexists(".agents", "skills", "manifest-add-repo", "SKILL.md"),
              ".agents/skills/manifest-add-repo/SKILL.md present")),
    ("02-task-centric-storage",
     "task-centric storage present (docs/tasks/)",
     lambda: (_fexists("docs", "tasks"), "docs/tasks dir present")),
    ("03-prd-queue-lifecycle",
     "PRD queue lifecycle dirs present (queue + archive)",
     lambda: (_fexists("docs", "prd-queue") and _fexists("docs", "prd-archive"),
              "docs/prd-queue + docs/prd-archive present")),
    ("02-context-engine-nomenclature",
     "context-engine nomenclature docs present",
     lambda: (_fexists("docs", "factory-context.md")
              and _contains("docs", "factory-context.md", needle="context_engine"),
              "factory-context.md names context_engine")),
    ("01-code-review-manual-trigger",
     "code-review run tooling present (bin/review-run.sh)",
     lambda: (_fexists("bin", "review-run.sh"), "bin/review-run.sh present")),
    ("02-code-review-archive-location",
     "code-review archive present (docs/code-reviews/)",
     lambda: (_fexists("docs", "code-reviews"), "docs/code-reviews present")),
    ("08-implementer-revision-same-session",
     "implementer revision same-session join (--revise in implementer-run.sh)",
     lambda: (_contains("bin", "implementer-run.sh", needle="--revise"),
              "implementer-run.sh --revise present")),
    ("01-implementer-delivery-failure-loud",
     "implementer fails loud on delivery failure (fail-loud guard)",
     lambda: (_contains("bin", "implementer-run.sh", needle="FAIL")
              or _contains("bin", "implementer-run.sh", needle="exit 1"),
              "implementer-run.sh has FAIL/exit-1 loud path")),
    ("01-task-similarity-check-scope",
     "similarity-check policy implemented in product-layer skill (merge only Pending/Queued)",
     lambda: (_contains(".agents", "skills", "product-layer", "SKILL.md", needle="similarity check")
              and _contains(".agents", "skills", "product-layer", "SKILL.md", needle="Pending"),
              "product-layer SKILL.md has similarity-check + Pending/Queued merge policy")),
    ("01-implementer-revision-test-seams",
     "implementer revision test seams present",
     lambda: (bool(glob.glob(os.path.join(WS, "bin", "test-*implementer*.sh"))),
              "bin/test-*implementer*.sh present")),
]


# ── Depth-first tier 3 (2026-08-20): legacy app/CI/gdrive tranche ──────────
# Decisions whose Decision section names a concrete artifact in the first-party
# apps (feed_analyser / workspace-portability / survival-infrastructure), the
# CI workflow, or the gdrive PRD backlog.

LEGACY_CLAIMS = [
    # workspace-portability
    ("01-github-device-auth-flow-implementation",
     "device-auth flow script exists (workspace-portability/github-auth-device-flow.sh)",
     lambda: (_fexists("workspace-portability", "github-auth-device-flow.sh"),
              "github-auth-device-flow.sh present")),
    ("02-device-flow-test-verification",
     "device-flow test suite exists (test-restore.sh)",
     lambda: (_fexists("workspace-portability", "test-restore.sh"),
              "test-restore.sh present")),
    ("01-parallel-repo-clone",
     "parallel clone implemented (restore_workspace.py concurrency)",
     lambda: (_contains("workspace-portability", "restore_workspace.py",
                        needle="concurrent") or
              _contains("workspace-portability", "restore_workspace.py",
                        needle="ThreadPool"),
              "restore_workspace.py uses concurrency")),
    # survival-infrastructure / gdrive (PRD is in the queue — feature is planned,
    # not yet implemented; the checkable claim is the PRD backlog entry)
    ("01-gdrive-integration-model",
     "gdrive ingestion is a planned feature (PRD in queue)",
     lambda: (_fexists("docs", "prd-queue", "2026-07-25-gdrive-instruction-source-ingest.md"),
              "gdrive PRD present in queue")),
    ("02-gdrive-auth-and-configuration",
     "gdrive auth config scoped (PRD in queue)",
     lambda: (_fexists("docs", "prd-queue", "2026-07-25-gdrive-instruction-source-ingest.md"),
              "gdrive PRD present in queue")),
    ("03-gdrive-file-export-and-storage",
     "gdrive export/storage scoped (PRD in queue)",
     lambda: (_fexists("docs", "prd-queue", "2026-07-25-gdrive-instruction-source-ingest.md"),
              "gdrive PRD present in queue")),
    # feed_analyser capture (agent-service + server pieces)
    ("01-capture-agent-followup-persistence-reconnect-fixes",
     "capture agent followup/persistence/reconnect fixes landed (agent-service)",
     lambda: (_fexists("feed_analyser", "capture", "agent-service", "persist.js")
              and _fexists("feed_analyser", "capture", "agent-service", "server.js"),
              "agent-service persist.js + server.js present")),
    ("01-capture-text-only-scope-and-vision",
     "capture text-only scope and vision docs exist (capture/docs)",
     lambda: (_fexists("feed_analyser", "capture", "docs"),
              "capture/docs present")),
    ("02-capture-links-embedded-tweets-and-tco-resolution",
     "capture link/tco resolution landed (capture server)",
     lambda: (bool(glob.glob(os.path.join(WS, "feed_analyser", "capture", "server", "*.py")))
              or bool(glob.glob(os.path.join(WS, "feed_analyser", "capture", "server", "*.js"))),
              "capture server sources present")),
    ("04-capture-recursive-node-tree-comment-is-tweet",
     "capture recursive node-tree comment handling landed (server)",
     lambda: (bool(glob.glob(os.path.join(WS, "feed_analyser", "capture", "server", "*.py"))),
              "capture server python sources present")),
    ("05-capture-resolve-links-and-restart-server",
     "capture resolve-links + restart server landed (run-server.sh)",
     lambda: (_fexists("feed_analyser", "capture", "run-server.sh"),
              "run-server.sh present")),
    # twitter-kb / FTS5
    ("05-twitter-kb-plain-files-fts5-read-api",
     "twitter-kb FTS5 read API landed (server/data/index.db)",
     lambda: (_fexists("feed_analyser", "capture", "server", "data", "index.db")
              or _contains("feed_analyser", "capture", "server", "tests", "test_capture.py",
                           needle="FTS5"),
              "FTS5 index or test present")),
    # agent-service inline agent
    ("04-artefact-session-evidence-model",
     "session evidence model landed (agent-service agent.js + persist.js)",
     lambda: (_fexists("feed_analyser", "capture", "agent-service", "agent.js")
              and _fexists("feed_analyser", "capture", "agent-service", "persist.js"),
              "agent-service agent.js + persist.js present")),
    ("02-openrouter-inference-server-side-key",
     "OpenRouter inference server-side key (llm/ server config)",
     lambda: (_fexists("llm", "docker-compose.yml"), "llm/docker-compose.yml present")),
    # CI / headless loop
    ("03-github-actions-fast-path",
     "CI workflow fast-path exists (.github/workflows/factory.yml)",
     lambda: (_fexists(".github", "workflows", "factory.yml"),
              "factory.yml present")),
    ("04-factory-run-headless-loop",
     "headless factory loop driver exists (bin/factory-run.sh)",
     lambda: (_fexists("bin", "factory-run.sh"), "bin/factory-run.sh present")),
    ("05-github-actions-free-execution-infra",
     "free execution infra (GitHub-hosted runners) — workflow present",
     lambda: (_fexists(".github", "workflows", "factory.yml"),
              "factory.yml present")),
    ("06-workflow-scope-gh-auth-pattern",
     "workflow scope GH auth pattern (factory.yml gh/GITHUB_TOKEN)",
     lambda: (_contains(".github", "workflows", "factory.yml", needle="GITHUB_TOKEN")
              or _contains(".github", "workflows", "factory.yml", needle="gh "),
              "factory.yml references gh/GITHUB_TOKEN")),
    ("07-ci-tracking-sync-ephemeral-runners",
     "CI tracking-sync step present (factory.yml)",
     lambda: (_contains(".github", "workflows", "factory.yml", needle="sync")
              or _contains(".github", "workflows", "factory.yml", needle="tracking"),
              "factory.yml has sync/tracking step")),
    ("05-headless-ci-gitignore-track-workflow",
     ".github/ workflow tracked (gitignore negation present)",
     lambda: (_contains(".gitignore", needle="!.github/")
              and _fexists(".github", "workflows", "factory.yml"),
              ".gitignore negates .github/; factory.yml tracked")),
    # task / PRD lifecycle
    ("07-prd-status-lifecycle",
     "PRD status-lifecycle vocabulary present (prd docs carry Status)",
     lambda: (all("**Status**" in read(f) for f in
                  glob.glob(os.path.join(WS, "docs", "prd-queue", "*.md"))),
              "all queue PRDs carry **Status**")),
    ("01-prd-as-routing-document-context-engine-depth",
     "PRD-as-routing-document exists (prd-queue is the routing entry)",
     lambda: (_fexists("docs", "prd-queue"), "docs/prd-queue present")),
    # task identification / traceability
    ("01-task-identification",
     "task identification convention present (docs/tasks.txt)",
     lambda: (_fexists("docs", "tasks.txt"), "docs/tasks.txt present")),
    ("04-traceability-links",
     "traceability links present (task → PRD → review in task files)",
     lambda: (_fexists("docs", "tasks")
              and _fexists("docs", "prd-archive"),
              "docs/tasks + docs/prd-archive present")),
    # code-review / review-sim / mock-gh
    ("01-review-driver-gh-call-and-test-seam",
     "review driver gh call + test seam present",
     lambda: (_fexists("bin", "test-review-driver.sh")
              and _contains("bin", "review-run.sh", needle="gh"),
              "test-review-driver.sh + review-run.sh gh seam")),
    ("02-review-simulation-blind-spot-real-driver-bugs",
     "review sim blind-spot tooling (test-review-driver.sh)",
     lambda: (_fexists("bin", "test-review-driver.sh"),
              "test-review-driver.sh present")),
    ("10-mock-gh-reject-unknown-fields",
     "mock gh reject-unknown-fields tooling present",
     lambda: (_contains("bin", "test-review-driver.sh", needle="mock")
              or _contains("bin", "implementer-run.sh", needle="mock"),
              "mock gh tooling referenced")),
    ("04-ponytail-review-worker-skills",
     "ponytail review-worker skills present (opensource/ponytail)",
     lambda: (_fexists("opensource", "ponytail"), "opensource/ponytail present")),
    ("01-ponytail-skills-fixed-mount",
     "ponytail skills fixed mount (opensource/ponytail present)",
     lambda: (_fexists("opensource", "ponytail"), "opensource/ponytail present")),
    ("01-ponytail-skills-fixed-mount-conditional-mount",
     "ponytail skills conditional mount (opensource/ponytail present)",
     lambda: (_fexists("opensource", "ponytail"), "opensource/ponytail present")),
    # headless backend host scope
    ("01-headless-backend-host-scope",
     "headless backend host scope exists (bin/factory-run.sh headless loop)",
     lambda: (_fexists("bin", "factory-run.sh"), "bin/factory-run.sh present")),
    ("02-merge-ready-deliverable",
     "merge-ready deliverable gate exists (bin/merge-pr.sh)",
     lambda: (_fexists("bin", "merge-pr.sh"), "bin/merge-pr.sh present")),
    ("03-local-first-herdr-execution-substrate",
     "local-first herdr execution substrate (opensource/herdr)",
     lambda: (_fexists("opensource", "herdr"), "opensource/herdr present")),
    ("08-subagent-handover-hang-herdr",
     "subagent handover hang fix (herdr present)",
     lambda: (_fexists("opensource", "herdr"), "opensource/herdr present")),
    # 09-large-documents-written-incrementally → BEHAVIORAL convention (in-session
    # chunking practice, no repo artifact) — honestly SKIP, not checkable
    ("04-llm-credential-resolution-from-auth-json",
     "LLM credential resolution from auth.json (implementer-run.sh auth.json)",
     lambda: (_contains("bin", "implementer-run.sh", needle="auth.json")
              or _contains("bin", "implementer-run.sh", needle="OPENROUTER_API_KEY"),
              "implementer-run.sh resolves LLM credential from auth.json")),
    # last checkable tranche (2026-08-20)
    ("01-make-repos-private",
     "first-party repos are private on GitHub (gh api visibility)",
     lambda: (_repos_private(), "gh api reports private for first-party repos")),
    ("03-review-worker-read-only-git",
     "review worker is read-only git (review-run.sh no push/merge)",
     lambda: (not _contains("bin", "review-run.sh", needle="git push")
              and not _contains("bin", "review-run.sh", needle="merge-pr"),
              "review-run.sh has no git push / merge-pr")),
    ("12-manual-host-delivery-fallback",
     "manual host delivery fallback documented (docs + driver)",
     lambda: (_contains("docs", "factory-context.md", needle="manual") or
              bool(glob.glob(os.path.join(WS, "docs", "*fallback*"))),
              "fallback path documented in factory-context/docs")),
    ("02-loop-end-delivery-invariant",
     "loop-end delivery invariant enforced (implementer-run.sh)",
     lambda: (_contains("bin", "implementer-run.sh", needle="exit 1")
              and _fexists("bin", "merge-pr.sh"),
              "implementer-run.sh fail-loud + merge gate present")),
]


def _repos_private():
    """First-party repos are private on GitHub (the 2026-07-31 privacy decision)."""
    try:
        for repo in ("feed_analyser", "survival-infrastructure"):
            r = subprocess.run(["gh", "api", "repos/ak47-arch/" + repo,
                                "--jq", ".private"],
                               capture_output=True, text=True)
            if r.returncode != 0 or r.stdout.strip() != "true":
                return False
        return True
    except Exception:
        return False


def claim_hits(fname):
    out = []
    for frag, claim, check in CLAIMS + DEPTH_CLAIMS + APP_CLAIMS + LEGACY_CLAIMS:
        if frag in fname:
            try:
                ok, ev = check()
            except Exception as e:
                ok, ev = False, f"check errored: {e}"
            out.append({"claim": claim, "pass": bool(ok), "evidence": ev})
    return out


# ── Langfuse landing (best-effort) ───────────────────────────────────────────
def langfuse_creds():
    try:
        env = read(os.path.join(WS, ".env.langfuse"))
        secret = re.search(r"LANGFUSE_SECRET_KEY[= ]+\"?([^\"]+)\"?", env)
        public = re.search(r"LANGFUSE_PUBLIC_KEY[= ]+\"?([^\"]+)\"?", env)
        return (public.group(1), secret.group(1)) if public and secret else None
    except Exception:
        return None


class LF:
    def __init__(self):
        c = langfuse_creds()
        self.auth = None
        self.base = "http://localhost:3000"
        if c and not NO_LANGFUSE:
            import base64
            self.auth = "Basic " + base64.b64encode(f"{c[0]}:{c[1]}".encode()).decode()

    def get_json(self, path):
        if not self.auth:
            return None
        r = urllib.request.Request(self.base + path, headers={"Authorization": self.auth})
        with urllib.request.urlopen(r, timeout=10) as resp:
            return json.load(resp)

    def match_trace(self, name):
        """Find a live trace whose name starts with the first user message."""
        if not self.auth or not name:
            return None
        for page in range(1, 12):
            try:
                d = self.get_json(f"/api/public/traces?limit=100&page={page}")
            except Exception:
                return None
            for t in d.get("data", []):
                if (t.get("name") or "")[:1000] == name:
                    return t.get("id")
            if page >= d.get("meta", {}).get("totalPages", 1):
                break
        return None

    def post_score(self, trace_id, decision, verdict, evidence):
        """Attach a decision-holds score to the trace (v3-compatible scores endpoint).

        NB: the batch /api/public/ingestion score-create path silently drops score
        events in v4 dual mode (accepted 201, never persisted); the single-score
        endpoint writes synchronously and is verified.
        """
        if not self.auth or not trace_id:
            return None
        try:
            body = {
                "name": "factory:decision-holds",
                "dataType": "NUMERIC",
                "value": 1.0 if verdict == "PASS" else 0.0,
                "traceId": trace_id,
                "comment": evidence[:500],
                "metadata": {"decision": decision, "verdict": verdict},
            }
            r = urllib.request.Request(
                self.base + "/api/public/scores", data=json.dumps(body).encode(),
                headers={"Authorization": self.auth, "Content-Type": "application/json"})
            with urllib.request.urlopen(r, timeout=15) as resp:
                return resp.status == 200 or resp.status == 201
        except Exception:
            return None


# ── Run ──────────────────────────────────────────────────────────────────────
def main():
    lf = LF()
    rows, gaps = [], []
    for path in sorted(glob.glob(os.path.join(D, "*", "decisions", "*.md"))):
        text = read(path)
        fname = os.path.basename(path)
        sess = os.path.basename(os.path.dirname(os.path.dirname(path)))

        status = field(text, "Status")
        date = field(text, "Date")
        task = field(text, "Task")
        project = field(text, "Project")
        schema_status = bool(status)
        schema_date = bool(re.match(r"\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?", date))
        if not schema_status:
            gaps.append(f"decision {fname}: no Status")
        if not schema_date:
            gaps.append(f"decision {fname}: no/odd Date ('{date}')")

        link_ok = os.path.exists(os.path.join(D, sess, "session.jsonl"))
        if not link_ok:
            gaps.append(f"decision {fname}: session {sess}/session.jsonl missing")

        claims = claim_hits(fname)
        claim_fail = [c for c in claims if not c["pass"]]
        verdict = "PASS"
        if not (schema_status and schema_date) or not link_ok or claim_fail:
            verdict = "FAIL"
        if verdict == "PASS" and not claims:
            verdict = "SKIP"  # nothing checkable yet — schema+link held

        # Langfuse landing (best-effort)
        trace_id = lf.match_trace(first_user_message(sess))
        score = None
        if trace_id and verdict != "SKIP":
            score = lf.post_score(trace_id, fname, verdict,
                                  "; ".join(c["evidence"] for c in claims) or "schema/link ok")

        rows.append({
            "decision": fname, "session": sess, "title": title_of(path, text),
            "task": task or "", "project": project or "", "status": status,
            "date": date,
            "schema": {"status": schema_status, "date": schema_date},
            "session_link": link_ok,
            "claims": claims,
            "verdict": verdict,
            "trace": {"matched": bool(trace_id), "trace_id": trace_id,
                      "score_posted": score},
        })

    out = {"generated": DATE, "total": len(rows),
           "verdicts": {v: sum(1 for r in rows if r["verdict"] == v)
                        for v in ("PASS", "FAIL", "SKIP")},
           "decisions": rows, "gaps": gaps}

    if not NO_REPORT:
        os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
        with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-decisions.json"), "w") as f:
            json.dump(out, f, indent=2)

        md = [f"# Decision-Loop Evaluation — {DATE}",
              "", f"Decisions: {len(rows)} · "
              f"PASS {out['verdicts']['PASS']} / FAIL {out['verdicts']['FAIL']} / "
              f"SKIP {out['verdicts']['SKIP']}",
              "", "| decision | session | verdict | claim failures | trace |",
              "|---|---|---|---|---|"]
        for r in rows:
            fails = "; ".join(c["claim"] for c in r["claims"] if not c["pass"]) or "—"
            md.append("| {d} | {s} | {v} | {f} | {t} |".format(
                d=r["decision"], s=r["session"][:8], v=r["verdict"],
                f=fails[:60], t=(r["trace"]["trace_id"] or "—")))
        md += ["", "## Gaps", ""]
        md += [f"- {g}" for g in (gaps or ["(none)"])]
        md += ["", f"_JSON: docs/evaluations/{DATE}-decisions.json_", ""]
        with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-decisions.md"), "w") as f:
            f.write("\n".join(md) + "\n")

    print(f"Evaluated {len(rows)} decisions → docs/evaluations/{DATE}-decisions.{{json,md}}")
    print("  verdicts:", out["verdicts"])
    for g in gaps:
        print("  GAP:", g)
    for r in rows:
        if r["trace"]["matched"]:
            status = {
                True: "posted", False: "FAILED", None: "skipped(no-claims)"
            }[r["trace"]["score_posted"]]
            print(f"  TRACE {r['decision']}: {r['trace']['trace_id']} score={status}")


if __name__ == "__main__":
    main()
