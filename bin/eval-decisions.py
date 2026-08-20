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
import glob, hashlib, json, os, re, sys, urllib.request, uuid
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


def claim_hits(fname):
    out = []
    for frag, claim, check in CLAIMS:
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
