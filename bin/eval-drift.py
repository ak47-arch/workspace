#!/usr/bin/env python3
"""S5 drift / L2 eval panel (breadth-first surface expansion).

Cross-run: does an earlier FIX stay fixed?  Where S1/S3/S4/S8/S9 grade a current
claim, S5 audits the *reversion risk of prior findings* — the L2 layer.  Each
verified-fixed finding (a "gold" row) is re-checked on the latest state.  A row
is:

  HOLD   — the fix still holds (was verified before, still green now)
  DRIFT  — a previously-green fix has REGRESSED / reverted (re-alarm)

The panel emits a drift table with first/last-verified so re-running the script
across the factory's evolution shows whether fixes *stay* fixed or come undone,
and FAILs (0.0) if any gold regresses.

Score caveat: v4 scores must write via synchronous POST /api/public/scores —
the batch /api/public/ingestion score-create path silently drops scores in
v4 dual mode.
"""
import glob
import json
import os
import re
import subprocess
import urllib.request
from datetime import date

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATE = date.today().isoformat()
NO_LANGFUSE = os.environ.get("NO_LANGFUSE") == "1"


def read(p):
    try:
        with open(p) as f:
            return f.read()
    except Exception:
        return ""


def _fexists(*rel):
    return os.path.isfile(os.path.join(WS, *rel))


def _git(args):
    r = subprocess.run(["git", "-C", WS] + args, capture_output=True, text=True)
    return (r.stdout or "").strip()


# ── gold rows: previously-verified fixes across the live surfaces ─────────
# Each row names the gold (what was fixed + when), then a check() that returns
# (ok:bool, evidence:str) against the CURRENT state.  If an earlier-verified
# row regresses, it flips to DRIFT.
def s1_dual_mode_fix():
    env = read(os.path.join(WS, "opensource", "langfuse", ".env"))
    compose = read(os.path.join(WS, "opensource", "langfuse", "docker-compose.yml"))
    pinned = "LANGFUSE_MIGRATION_V4_WRITE_MODE=dual" in env
    anchor = "LANGFUSE_MIGRATION_V4_WRITE_MODE" in compose
    ok = pinned and anchor
    why = "dual-mode anchor in compose; .env write-mode=dual" if ok else (
        "missing .env pin" if not pinned else "missing compose anchor")
    return ok, why


def s1_session_retention():
    # every decision session keeps its session.jsonl evidence (PR #24 fix)
    sess = os.path.join(WS, "docs", "knowledge", "sessions")
    missing = []
    if os.path.isdir(sess):
        for d in os.listdir(sess):
            if not os.path.isdir(os.path.join(sess, d)):
                continue
            if not os.path.isfile(os.path.join(sess, d, "session.jsonl")):
                missing.append(d)
    return not missing, "all decision sessions retain session.jsonl" + (
        " (missing: " + ", ".join(missing) + ")" if missing else "")


def s3_orphan_indexed():
    idx = read(os.path.join(WS, "docs", "knowledge", "index.md"))
    orphan = "01-ponytail-skills-fixed-mount-conditional-mount.md" in idx \
        or "0ded66e7" in idx
    return orphan, "orphaned decision (ponytail-skills-fixed-mount-conditional-mount) reachable in index" if orphan \
        else "orphaned decision MISSING from index (re-drifted)"


def s4_legacy_markers():
    legacy = ["github-browser-auth-flow", "x-capture-instrument",
              "extend-software-factory-wsff", "task-file-dashboard",
              "implementer-agent", "ponytail-skills-fixed-mount",
              "sandbox-credential-mounting"]
    missing = [t for t in legacy
               if "## PR tracking" not in read(os.path.join(WS, "docs", "tasks", t + ".md"))
               or "pre-PR-era" not in read(os.path.join(WS, "docs", "tasks", t + ".md"))]
    return not missing, "all 7 legacy tasks carry pre-PR-era marker" if not missing \
        else "markers missing: " + ", ".join(missing)


def s4_verdict_repair():
    t = read(os.path.join(WS, "docs", "tasks", "implementer-ponytail.md"))
    return "verdict APPROVE" in t, "implementer-ponytail final review recorded as APPROVE"


def s8_roster_closed():
    triads = [("prd-reviewer", "prd-reviewer-ops", "prd-reviewer-agent.md"),
              ("implementer", "implementer-ops", "implementer-agent.md"),
              ("code-reviewer", "review-ops", "reviewer-agent.md"),
              ("evaluator", "eval-ops", "evaluator-agent.md")]
    miss = [n for n, sk, rf in triads
            if not (_fexists(".pi", "agents", n + ".md")
                    and _fexists(".agents", "skills", sk, "SKILL.md")
                    and _fexists("docs", "reference", rf))]
    return not miss, "all 4 roster agents have complete triads" if not miss \
        else "incomplete triads: " + ", ".join(miss)


def s9_key_advisory():
    """No NEW secret-key class leaked beyond the pre-existing tr language — the
    langfuse keys stay bound to the local instance (accepted-risk), and no new
    provider key shape (sk-or/sk-ant/etc) drifted into tracked files."""
    key_re = re.compile(
        r"(sk-(?:or-v1|ant|proj|svcacct|user)-[A-Za-z0-9_\-]{10,}|"
        r"(?:pk|sk)-lf-[A-Za-z0-9_\-]{10,}|"
        r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)")
    new_classes = []
    for rel in _git(["ls-files"]).splitlines():
        text = read(os.path.join(WS, rel))
        for m in key_re.finditer(text):
            body = m.group(0).split("=", 1)[-1]
            if "PRIVATE KEY-----" in body and not body.endswith("-----"):
                continue
            if any(w in body.lower() for w in ("test", "example", "dummy", "override", "placeholder")):
                continue
            # lf- keys are the pre-existing accepted-risk class; any other prefix is a regression
            if "-lf-" not in body and "lf-" not in body:
                new_classes.append(f"{rel}: {body[:8]}…")
    return not new_classes, "no new key class leaked (only pre-existing local langfuse keys)" \
        if not new_classes else "NEW keys: " + "; ".join(new_classes)


def s7_spine_links():
    """The discovery spine's pointer network resolves — every relative link in
    factory-context.md points at a real file (the openwiki ../ fix)."""
    path = os.path.join(WS, "docs", "factory-context.md")
    text = read(path)
    base = os.path.dirname(path)
    broken = []
    total = 0
    for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
        target = m.group(1).strip()
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        total += 1
        p = target.split("#", 1)[0]
        if p and not os.path.exists(os.path.normpath(os.path.join(base, p))):
            broken.append(target)
    return not broken, "all {} factory-context links resolve".format(total) if not broken \
        else "broken spine links: " + "; ".join(broken)


def s7_footprint():
    """Leanness holds — AGENTS.md + factory-context.md stay within budgets."""
    agents = len(read(os.path.join(WS, "AGENTS.md"))) // 4
    fc = len(read(os.path.join(WS, "docs", "factory-context.md"))) // 4
    ok = agents <= 1200 and fc <= 4500
    return ok, "AGENTS.md ~{} tok, factory-context ~{} tok (lean)".format(agents, fc) if ok \
        else "AGENTS.md ~{} tok or factory-context ~{} tok over budget".format(agents, fc)


def _slugify(p):
    b = os.path.basename(p)
    m = re.match(r"^\d{4}-\d{2}-\d{2}-(.+)\.md$", b)
    return m.group(1) if m else b.replace(".md", "")


def _task_status(slug):
    m = re.search(r"\*\*Status\*\*:\s*(.+)$",
                  read(os.path.join(WS, "docs", "tasks", slug + ".md")) or "", re.M)
    return (m.group(1).strip().lower() if m else "")


def _s2_pr_tracking(slug):
    txt = read(os.path.join(WS, "docs", "tasks", slug + ".md"))
    m = re.search(r"## PR tracking(.*?)(?=\n## |\Z)", txt, re.S)
    if not m:
        return {"has_pr": False, "pre_pr_era": False, "merge_sha": None, "reviews": []}
    block = m.group(1)
    prs = re.findall(r"^- PR: #(\d+) (\S+)$", block, re.M)
    merges = re.findall(r"^- Merge: ([0-9a-f]{7,})", block, re.M)
    reviews = re.findall(r"^- Review: session ([\w-]+) · verdict (APPROVE|REQUEST_CHANGES|n/a|REVISE)", block, re.M)
    return {"has_pr": bool(prs), "pre_pr_era": "pre-PR-era" in block,
            "merge_sha": merges[-1] if merges else None, "reviews": reviews}


def s2_uat_gate_closed():
    """S2 T2 invariant — no COMPLETE task's PRD is still queued (UAT gate closed)."""
    queued = {_slugify(p) for p in glob.glob(os.path.join(WS, "docs/prd-queue", "*.md"))}
    archived = {_slugify(p) for p in glob.glob(os.path.join(WS, "docs/prd-archive", "*.md"))}
    bad = [s for s in queued if _task_status(s) in ("complete", "completed") and s not in archived]
    return not bad, "no complete task's PRD still queued" if not bad \
        else "UAT gate open: " + ", ".join(bad)


def s2_merge_approve():
    """S2 T4 + S4 P5 invariant — every MERGED task's last review is APPROVE."""
    bad = []
    for f in glob.glob(os.path.join(WS, "docs/tasks", "*.md")):
        slug = _slugify(f)
        tr = _s2_pr_tracking(slug)
        if not tr["merge_sha"] or tr["pre_pr_era"]:
            continue
        last = tr["reviews"][-1][1].upper() if tr["reviews"] else None
        if last != "APPROVE":
            bad.append(f"{slug} (last review {last or 'none'})")
    return not bad, "all merged tasks last-review APPROVE" if not bad \
        else "merged w/o APPROVE: " + "; ".join(bad)


def s2_merged_complete():
    """S2 T5 invariant — a merged task is complete (no merged-but-still-open)."""
    bad = []
    for f in glob.glob(os.path.join(WS, "docs/tasks", "*.md")):
        slug = _slugify(f)
        tr = _s2_pr_tracking(slug)
        if not tr["merge_sha"] or tr["pre_pr_era"]:
            continue
        if _task_status(slug) not in ("complete", "completed"):
            bad.append(f"{slug} (status {_task_status(slug) or '?'})")
    return not bad, "all merged tasks complete" if not bad else "merged not complete: " + "; ".join(bad)


def s4_report_body_fidelity():
    """S4 P4 invariant — a task's ROOT review verdict matches its review report body.
    Only the final review is cross-checked (the on-disk report reflects the last write)."""
    bad = []
    for f in glob.glob(os.path.join(WS, "docs/tasks", "*.md")):
        slug = _slugify(f)
        txt = read(f)
        m = re.search(r"## PR tracking(.*?)(?=\n## |\Z)", txt, re.S)
        if not m:
            continue
        # last review line's report dir points at a real report whose body matches
        dirs = re.findall(r"report\s+docs/code-reviews/(\S+)/", m.group(1))
        if not dirs:
            continue
        rd = dirs[-1]
        rp = os.path.join(WS, "docs", "code-reviews", rd, "report.md")
        body = None
        if os.path.isfile(rp):
            bm = re.search(r"##\s*Verdict\s*\n+\s*\*{0,2}(APPROVE|REQUEST_CHANGES|REVISE|n/a)",
                           read(rp), re.I)
            body = bm.group(1).upper() if bm else None
        # last review verdict as recorded in task
        vs = re.findall(r"· verdict\s+(APPROVE|REQUEST_CHANGES|REVISE|n/a)", m.group(1), re.I)
        rec = vs[-1].upper() if vs else None
        if rec and rec != "N/A" and (body is None or rec != body):
            bad.append(f"{slug} (recorded {rec}, body {body or '?'})")
    return not bad, "final review verdict equals report body" if not bad \
        else "report-body mismatch: " + "; ".join(bad)


def _load_sibling(mod):
    """Import a bin/*.py sibling by path (bin/ is not a package)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(mod, os.path.join(WS, "bin", mod + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def s3_session_resolvable():
    """S3 K4 invariant — every decision resolves to a session.jsonl (depth fix)."""
    _k = _load_sibling("eval-knowledge")  # reuse the same resolver
    _rows, missing = _k.session_resolvable()
    return not missing, "all decisions resolve to session.jsonl" if not missing \
        else "unresolved: " + "; ".join(missing)


def s7_section_balance():
    """S7 C4 invariant — no single factory-context section exceeds the 45% share cap."""
    _c = _load_sibling("eval-context")
    _rows, fails = _c.intra_doc_sections()
    return not fails, "factory-context sections balanced (max share under 45%)" if not fails \
        else "; ".join(fails)


def s7_no_dangling_backref():
    """S7 C5 invariant — no link targets an anchor that isn't a defined heading."""
    _c = _load_sibling("eval-context")
    _rows, dangling = _c.reverse_reachability()
    return not dangling, "no dangling back-references in spine" if not dangling \
        else "; ".join(dangling)


GOLD = [
    {"id": "s1-dual-mode", "surface": "S1", "desc": "dual-mode drift pinned (compose + .env)",
     "first": "2026-08-20", "check": s1_dual_mode_fix},
    {"id": "s1-session-retention", "surface": "S1", "desc": "decision session.jsonl retained (PR #24)",
     "first": "2026-08-20", "check": s1_session_retention},
    {"id": "s3-orphan-indexed", "surface": "S3", "desc": "orphaned decision indexed + reachable",
     "first": "2026-08-20", "check": s3_orphan_indexed},
    {"id": "s4-legacy-markers", "surface": "S4", "desc": "7 legacy tasks honestly marked pre-PR-era",
     "first": "2026-08-20", "check": s4_legacy_markers},
    {"id": "s4-verdict-repair", "surface": "S4", "desc": "implementer-ponytail final verdict=APPROVE",
     "first": "2026-08-20", "check": s4_verdict_repair},
    {"id": "s8-roster-closed", "surface": "S8", "desc": "roster triads complete (incl. prd-reviewer)",
     "first": "2026-08-20", "check": s8_roster_closed},
    {"id": "s9-key-advisory", "surface": "S9", "desc": "no new key class leaked (only local langfuse)",
     "first": "2026-08-20", "check": s9_key_advisory},
    {"id": "s7-spine-links", "surface": "S7", "desc": "factory-context spine links resolve (openwiki ../ fix)",
     "first": "2026-08-20", "check": s7_spine_links},
    {"id": "s7-footprint", "surface": "S7", "desc": "AGENTS.md + factory-context stay lean (budgets)",
     "first": "2026-08-20", "check": s7_footprint},
    # S2 state-machine invariants + S4 P4 depth guards (registered after the S4/S2 passes)
    {"id": "s2-uat-gate-closed", "surface": "S2", "desc": "no complete task's PRD still queued (UAT gate)",
     "first": "2026-08-20", "check": s2_uat_gate_closed},
    {"id": "s2-merge-approve", "surface": "S2", "desc": "merged task's last review is APPROVE (T4)",
     "first": "2026-08-20", "check": s2_merge_approve},
    {"id": "s2-merged-complete", "surface": "S2", "desc": "merged task is complete (T5)",
     "first": "2026-08-20", "check": s2_merged_complete},
    {"id": "s4-report-body-fidelity", "surface": "S4", "desc": "final review verdict == report body (P4)",
     "first": "2026-08-20", "check": s4_report_body_fidelity},
    # S3/S7 depth fixes (2026-08-21)
    {"id": "s3-session-resolvable", "surface": "S3", "desc": "every decision resolves to session.jsonl (K4)",
     "first": "2026-08-21", "check": s3_session_resolvable},
    {"id": "s7-section-balance", "surface": "S7", "desc": "no factory-context section >45% share (C4)",
     "first": "2026-08-21", "check": s7_section_balance},
    {"id": "s7-no-dangling-backref", "surface": "S7", "desc": "no dangling back-reference in spine (C5)",
     "first": "2026-08-21", "check": s7_no_dangling_backref},
]


def run_drift():
    """Re-check each gold. Load prior drift.json if present to carry first/last
    verification across runs (DRIFT only if a previously-green row regresses)."""
    prev = {}
    pf = os.path.join(WS, "docs", "evaluations", "drift.json")
    if os.path.isfile(pf):
        try:
            prev = {r["id"]: r for r in json.load(open(pf)).get("rows", [])}
        except Exception:
            prev = {}

    rows, drifts = [], []
    for g in GOLD:
        ok, why = g["check"]()
        prior = prev.get(g["id"])
        status = "HOLD" if ok else "DRIFT"
        # a DRIFT row that was already green before = a re-alarm (regression)
        if not ok and prior and prior.get("status") == "HOLD":
            status = "DRIFT-REGRESSED"
        first = (prior or {}).get("first") or g["first"]
        last = DATE
        rows.append({"id": g["id"], "surface": g["surface"], "desc": g["desc"],
                     "first": first, "last": last, "status": status,
                     "ok": ok, "evidence": why})
        if not ok:
            drifts.append(f"{g['id']} ({g['surface']}): {g['desc']} — {why}")
    return rows, drifts


# ── Langfuse (fleet-level score on the latest trace) ───────────────────────
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

    def latest_trace(self):
        if not self.auth:
            return None
        try:
            d = json.load(urllib.request.urlopen(
                urllib.request.Request(self.base + "/api/public/traces?limit=1",
                                       headers={"Authorization": self.auth}), timeout=10))
            ts = d.get("data", [])
            return ts[0].get("id") if ts else None
        except Exception:
            return None

    def post_score(self, trace_id, name, value, evidence):
        if not self.auth or not trace_id:
            return None
        try:
            body = {"name": name, "dataType": "NUMERIC", "value": value,
                    "traceId": trace_id, "comment": evidence[:500],
                    "metadata": {"surface": name}}
            r = urllib.request.Request(
                self.base + "/api/public/scores", data=json.dumps(body).encode(),
                headers={"Authorization": self.auth, "Content-Type": "application/json"})
            with urllib.request.urlopen(r, timeout=15) as resp:
                return resp.status in (200, 201)
        except Exception:
            return None


# ── Run ─────────────────────────────────────────────────────────────────────
def main():
    rows, drifts = run_drift()
    verdict = "PASS" if not drifts else "FAIL"

    out = {"generated": DATE, "verdict": verdict,
           "rows": rows, "drifts": drifts}
    os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs", "evaluations", "drift.json"), "w") as f:
        json.dump(out, f, indent=2)

    md = [f"# Drift / L2 Evaluation — {DATE}",
          f"Verdict: **{verdict}** · gold rows {len(rows)} · drifts {len(drifts)}", "",
          "Cross-run check: did the previously fixed findings stay fixed?",
          "", "| row | surface | status | first | last | evidence |",
          "|---|---|---|---|---|---|"]
    for r in rows:
        md.append("| {} | {} | **{}** | {} | {} | {} |".format(
            r["id"], r["surface"], r["status"], r["first"], r["last"], r["evidence"]))
    md += ["", "## Drifts (regressions)", ""]
    md += [f"- {d}" for d in (drifts or ["(none — every gold still holds)"] )]
    md += ["", "_JSON: docs/evaluations/drift.json_", ""]
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-drift.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    lf = LF()
    tid = lf.latest_trace()
    if tid:
        ok = lf.post_score(tid, "factory:S5-drift", 1.0 if verdict == "PASS" else 0.0,
                           "; ".join(drifts) or "all gold rows hold")
        print(f"  SCORE factory:S5-drift: {tid} value={'1.0' if verdict=='PASS' else '0.0'} "
              f"{'posted' if ok else 'FAILED'}")

    print("Evaluated S5 drift → docs/evaluations/{}-drift.md (drift.json trend)".format(DATE))
    print("  verdict: " + verdict + (" (0 drifts)" if not drifts else " → " + "; ".join(drifts)))


if __name__ == "__main__":
    main()