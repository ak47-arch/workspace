#!/usr/bin/env python3
"""eval-pipeline.py — S2 task-loop panel: state-machine fidelity (PASS/FAIL).

Joins tasks ↔ PR tracking (dec 06) ↔ implementations ↔ code-reviews and grades
the task lifecycle state machine per factory-context:

    in-prd → prd-ready → in-progress → in-review → complete

Deterministic per-task checks:

  T1 state-legal       — task status is a valid lifecycle state
  T2 complete-closed   — a complete task's PRD is closed in the
                         routing manifest (UAT + user go-ahead gate: code+tests
                         ≠ complete). If the PRD is still open in the manifest →
                         FAIL. If no PRD exists anywhere → pre-PRD-era completion
                         (advisory, SKIP).
  T3 complete-evidence  — a complete task with PR tracking (post-dec-06) must
                         have an implementation report AND a code-review
                         report archived.  Pre-PR-era tasks are exempt.
  T4 merged-approved    — a task with a recorded merge must have an APPROVE on
                         record (last review).  n/a or missing APPROVE → FAIL.
  T5 merged-complete    — a merged task must be complete (no merged-but-still-
                         in-flight states).
  T6 gate-closed        — a task whose PRD is still open in the routing manifest
                         must NOT be complete (the gate STAYS closed until
                         settlement).

Verdict semantics (honesty rule): a row is PASS only when every checkable
claim holds; FAIL when a claim is violated; SKIP when nothing is checkable
yet (e.g. in-prd tasks with no PR).  Pre-PR-era tasks (no PR tracking, marked
or implied) are exempt from T3/T4/T5 by convention — the PR pipeline did not
exist for them.

Emits docs/evaluations/<date>-pipeline.{json,md} + a fleet-level Langfuse
score (synchronous POST /api/public/scores — batch ingestion silently drops
scores in v4 dual mode).
"""
import glob, json, os, re, subprocess, sys, urllib.request
from datetime import datetime

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATE = datetime.now().strftime("%Y-%m-%d")
NO_LANGFUSE = "--no-langfuse" in sys.argv

VALID_STATES = {"in-prd", "prd-ready", "in-progress", "in-review",
                "complete", "completed", "deferred", "blocked", "paused"}


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""


def slugify(p):
    b = os.path.basename(p).replace(".md", "")
    m = re.match(r"^\d{4}-\d{2}-\d{2}-(.+)$", b)
    return m.group(1) if m else b


def first_last_ts(sess_uuid):
    """First/last event timestamp from a session trace (lead-time proxy)."""
    p = os.path.join(WS, "docs/knowledge/sessions", sess_uuid, "session.jsonl")
    if not os.path.exists(p):
        return None, None
    ts = []
    try:
        with open(p) as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    t = json.loads(line).get("timestamp")
                    if t:
                        ts.append(t)
                except Exception:
                    pass
    except Exception:
        return None, None
    return (ts[0] if ts else None), (ts[-1] if ts else None)


def section(text, header, level=2):
    hashes = "#" * level
    m = re.search(rf"^{hashes} {re.escape(header)}[^\n]*$(.*?)(?=^#{{2,3}} |\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


# ── evidence inventory (routing manifest is the lifecycle source; no archive dir) ──
def _prd_status_rows():
    """slug → routing-manifest status for every PRD in the stable docs/prd/ home."""
    mf = os.path.join(WS, "docs", "prd", "manifest.json")
    try:
        with open(mf) as f:
            data = json.load(f)
    except Exception:
        return {}
    return {row.get("slug"): row.get("status") for row in data.get("prds", [])}

PRD_STATUS = _prd_status_rows()
# A PRD is open/queued while its routing-manif row is not yet settled; it is
# settled (archived-equivalent) once the row carries a terminal status
# ("final" = approved PRD, "closed" = task closed).
QUEUED = {slug for slug, st in PRD_STATUS.items() if st in ("draft", "open")}
ARCHIVED = {slug for slug, st in PRD_STATUS.items() if st in ("final", "closed")}
IMPL_DIRS = {slugify(p) for p in glob.glob(os.path.join(WS, "docs/implementations", "*"))
             if os.path.isdir(p)}
REV_DIRS = {slugify(p) for p in glob.glob(os.path.join(WS, "docs/code-reviews", "*"))
            if os.path.isdir(p)}


def parse_pr_tracking(txt):
    """Parse the (possibly multi-PR) PR-tracking block.  Returns the LAST PR's
    state: has_pr, pr_num, repo, url, merge_sha, reviews [(session, verdict)],
    pre_pr_era marker."""
    m = re.search(r"## PR tracking(.*?)(?=\n## |\Z)", txt, re.S)
    if not m:
        return {"has_pr": False, "pre_pr_era": False, "pr_num": None,
                "repo": None, "url": None, "merge_sha": None, "reviews": []}
    block = m.group(1)
    prs = re.findall(r"^- PR: #(\d+) (\S+)$", block, re.M)
    urls = re.findall(r"^- URL: (\S+)$", block, re.M)
    merges = re.findall(r"^- Merge: ([0-9a-f]{7,})", block, re.M)
    reviews = re.findall(r"^- Review: session ([\w-]+) · verdict (APPROVE|REQUEST_CHANGES|n/a|REVISE)",
                         block, re.M)
    pre_pr_era = "pre-PR-era" in block
    return {
        "has_pr": bool(prs),
        "pr_num": prs[-1][0] if prs else None,
        "repo": prs[-1][1] if prs else None,
        "url": urls[-1] if urls else None,
        "merge_sha": merges[-1] if merges else None,
        "reviews": reviews,
        "pre_pr_era": pre_pr_era,
    }


def task_checks(slug, status, txt, tracking):
    """Return (checks:list[dict], verdict, reasons).  SKIP when nothing checkable."""
    checks = []
    fails = []

    # T1 state-legal
    legal = status in VALID_STATES
    checks.append({"check": "T1 state-legal", "pass": legal,
                   "evidence": "status '{}'".format(status)})
    if not legal:
        fails.append("T1: invalid lifecycle state '{}'".format(status))

    complete = status in ("complete", "completed")
    pre_era = tracking["pre_pr_era"] or not tracking["has_pr"]

    # zero-evidence completions: no PRD anywhere, no impl, no review, no PR
    # tracking -> the completion is UNVERIFIABLE, not clean.  Honest status is
    # SKIP with an advisory (pre-factory legacy completions are not failures,
    # but neither are they verified).
    zero_evidence = (complete and slug not in ARCHIVED and slug not in QUEUED
                     and slug not in IMPL_DIRS and slug not in REV_DIRS
                     and not tracking["has_pr"])
    if zero_evidence:
        checks.append({"check": "T0 zero-evidence completion", "pass": None,
                       "evidence": "complete but no PRD/impl/rev anywhere (unverifiable)"})
        return checks, "SKIP", []

    # T2 complete-closed (UAT gate)
    if complete:
        if slug in QUEUED:
            checks.append({"check": "T2 complete-closed", "pass": False,
                           "evidence": "PRD still open in routing manifest (gate open)"})
            fails.append("T2: complete but PRD still open in routing manifest (UAT gate violated)")
        elif slug in ARCHIVED:
            checks.append({"check": "T2 complete-closed", "pass": True,
                           "evidence": "PRD closed in routing manifest"})
        else:
            checks.append({"check": "T2 complete-closed", "pass": None,
                           "evidence": "no PRD anywhere (pre-PRD-era)"})

    # T3 complete-evidence (post-PR-era only)
    if complete and tracking["has_pr"]:
        has_impl = slug in IMPL_DIRS
        has_rev = slug in REV_DIRS
        ok3 = has_impl and has_rev
        checks.append({"check": "T3 complete-evidence", "pass": ok3,
                       "evidence": "impl={} rev={}".format("Y" if has_impl else "-",
                                                           "Y" if has_rev else "-")})
        if not ok3:
            fails.append("T3: complete+PR-tracked missing {} evidence".format(
                "/".join(x for x, ok in (("impl", has_impl), ("rev", has_rev)) if not ok)))

    # T4 merged-approved
    if tracking["merge_sha"]:
        verdicts = [v for _, v in tracking["reviews"]]
        last = verdicts[-1] if verdicts else None
        approved = last == "APPROVE"
        checks.append({"check": "T4 merged-approved", "pass": approved,
                       "evidence": "last review {}".format(last or "«none»")})
        if not approved:
            fails.append("T4: merged without APPROVE (last review {})".format(last or "«none»"))

    # T5 merged-complete
    if tracking["merge_sha"]:
        ok5 = complete
        checks.append({"check": "T5 merged-complete", "pass": ok5,
                       "evidence": "merged + status '{}'".format(status)})
        if not ok5:
            fails.append("T5: merged but task not complete ('{}')".format(status))

    # T6 gate-closed
    if slug in QUEUED:
        ok6 = not complete
        checks.append({"check": "T6 gate-closed", "pass": ok6,
                       "evidence": "open-in-manifest + status '{}'".format(status)})
        if not ok6:
            fails.append("T6: PRD open in routing manifest but task complete")

    checkable = [c for c in checks if c["pass"] is not None]
    if fails:
        verdict = "FAIL"
    elif checkable and all(c["pass"] for c in checkable):
        verdict = "PASS"
    else:
        verdict = "SKIP"  # nothing checkable yet (e.g. in-prd, no PR)
    return checks, verdict, fails


def main():
    rows, gaps = [], []
    for task_file in sorted(glob.glob(os.path.join(WS, "docs/tasks", "*.md"))):
        slug = os.path.splitext(os.path.basename(task_file))[0]
        if slug == "README":
            continue
        t = read(task_file)
        m = re.search(r"^\*\*Status\*\*:\s*(\S+)", t, re.M)
        status = m.group(1) if m else "?"
        tracking = parse_pr_tracking(t)

        # existing data extraction (lead-time / review metrics)
        pr = re.search(r"^- PR: #(\d+) \((\S+)\)", t, re.M)
        raised = re.search(r"^- Raised by: implementer run ([0-9a-f-]{8,})", t, re.M)
        review = re.search(r"^- Review: session ([0-9a-f-]{8,}) · verdict (\S+)", t, re.M)
        i_text = read(glob.glob(os.path.join(WS, "docs/implementations", f"*-{slug}", "report.md"))[0]) \
            if glob.glob(os.path.join(WS, "docs/implementations", f"*-{slug}", "report.md")) else ""
        r_text = read(glob.glob(os.path.join(WS, "docs/code-reviews", f"*-{slug}", "report.md"))[0]) \
            if glob.glob(os.path.join(WS, "docs/code-reviews", f"*-{slug}", "report.md")) else ""
        vm = re.search(r"^## Verdict\s*\n(.+)", r_text, re.M)
        verdict = vm.group(1).strip() if vm else ("—" if r_text else "no review")
        _b = re.findall(r"^\- .*", section(r_text, "Blocking", level=3), re.M)
        blocking = len([x for x in _b if not x.strip().startswith("- None")])
        advisory = len(re.findall(r"^\- ", section(r_text, "Advisory", level=3), re.M))
        stories_pass = len(re.findall(r"^- \[PASS\]", r_text, re.M))
        stories_fail = len(re.findall(r"^- \[FAIL\]", r_text, re.M))
        impl_stories = len(re.findall(r"^- \*\*US\d+", i_text, re.M))

        raised_uuid = raised.group(1) if raised else None
        review_uuid = review.group(1) if review else None
        r0, r1 = first_last_ts(raised_uuid) if raised_uuid else (None, None)
        v0, v1 = first_last_ts(review_uuid) if review_uuid else (None, None)

        checks, s2_verdict, fails = task_checks(slug, status, t, tracking)
        if fails:
            gaps.append(f"task {slug}: " + "; ".join(fails))

        rows.append({
            "task": slug, "status": status,
            "pr": f"#{tracking['pr_num']}" if tracking["pr_num"] else None,
            "repo": tracking["repo"],
            "url": tracking["url"],
            "pre_pr_era": tracking["pre_pr_era"],
            "raised_by": raised_uuid, "raised_first_ts": r0, "raised_last_ts": r1,
            "review_session": review_uuid, "verdict": verdict,
            "review_first_ts": v0, "review_last_ts": v1,
            "merge_sha": tracking["merge_sha"],
            "impl_stories": impl_stories,
            "stories_pass": stories_pass, "stories_fail": stories_fail,
            "blocking_findings": blocking, "advisory_findings": advisory,
            "s2_verdict": s2_verdict,
            "checks": checks,
        })

    out = {"generated": DATE, "tasks": rows, "schema_gaps": gaps,
           "verdicts": {v: sum(1 for r in rows if r["s2_verdict"] == v)
                        for v in ("PASS", "FAIL", "SKIP")},
           "overall": "FAIL" if any(r["s2_verdict"] == "FAIL" for r in rows) else "PASS"}
    os.makedirs(os.path.join(WS, "docs/evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs/evaluations", f"{DATE}-pipeline.json"), "w") as f:
        json.dump(out, f, indent=2)

    md = [f"# Pipeline / Task-Loop Evaluation — {DATE}",
          f"Verdict: **{out['overall']}** · tasks {len(rows)} · "
          f"PASS {out['verdicts']['PASS']} / FAIL {out['verdicts']['FAIL']} / "
          f"SKIP {out['verdicts']['SKIP']}",
          "", "| task | status | PR | S2 | evidence (arch/impl/rev) | merge |",
          "|---|---|---|---|---|---|"]
    for r in rows:
        arch = "Y" if r["task"] in ARCHIVED else ("Q" if r["task"] in QUEUED else "-")
        md.append("| {} | {} | {} | {} | {} | {} |".format(
            r["task"], r["status"], r["pr"] or "—", r["s2_verdict"],
            arch + "/" + ("Y" if r["task"] in IMPL_DIRS else "-") + "/"
            + ("Y" if r["task"] in REV_DIRS else "-"),
            (r["merge_sha"][:8] if r["merge_sha"] else "—")))
    md += ["", "## State-machine checks", ""]
    md += ["| task | T1 | T2 | T3 | T4 | T5 | T6 |", "|---|---|---|---|---|---|---|"]
    for r in rows:
        cm = {c["check"]: ("✓" if c["pass"] is True else "✗" if c["pass"] is False else "·")
              for c in r["checks"]}
        md.append("| {} | {} | {} | {} | {} | {} | {} |".format(
            r["task"], cm.get("T1 state-legal", "·"), cm.get("T2 complete-closed", "·"),
            cm.get("T3 complete-evidence", "·"), cm.get("T4 merged-approved", "·"),
            cm.get("T5 merged-complete", "·"), cm.get("T6 gate-closed", "·")))
    md += ["", "## Verdict distribution", ""]
    for k, v in sorted(out["verdicts"].items()):
        md.append(f"- {k}: {v}")
    md += ["", "## Gaps (state-machine violations)", ""]
    md += [f"- {g}" for g in (gaps or ["(none)"])]
    md += ["", f"_JSON: docs/evaluations/{DATE}-pipeline.json_", ""]
    with open(os.path.join(WS, "docs/evaluations", f"{DATE}-pipeline.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    # fleet-level Langfuse score
    if not NO_LANGFUSE:
        try:
            env = read(os.path.join(WS, ".env.langfuse"))
            secret = re.search(r"LANGFUSE_SECRET_KEY[= ]+\"?([^\"]+)\"?", env)
            public = re.search(r"LANGFUSE_PUBLIC_KEY[= ]+\"?([^\"]+)\"?", env)
            if public and secret:
                import base64
                auth = "Basic " + base64.b64encode(
                    f"{public.group(1)}:{secret.group(1)}".encode()).decode()
                d = json.load(urllib.request.urlopen(
                    urllib.request.Request("http://localhost:3000/api/public/traces?limit=1",
                                           headers={"Authorization": auth}), timeout=10))
                ts = d.get("data", [])
                if ts:
                    body = {"name": "factory:S2-task-loop", "dataType": "NUMERIC",
                            "value": 1.0 if out["overall"] == "PASS" else 0.0,
                            "traceId": ts[0]["id"],
                            "comment": "; ".join(gaps) or "state machine holds",
                            "metadata": {"surface": "S2-task-loop"}}
                    r = urllib.request.Request(
                        "http://localhost:3000/api/public/scores",
                        data=json.dumps(body).encode(),
                        headers={"Authorization": auth, "Content-Type": "application/json"})
                    with urllib.request.urlopen(r, timeout=15) as resp:
                        print("  SCORE factory:S2-task-loop: {} value={} {}".format(
                            ts[0]["id"], 1.0 if out["overall"] == "PASS" else 0.0,
                            "posted" if resp.status in (200, 201) else "FAILED"))
        except Exception as e:
            print("  (no langfuse score:", e, ")")

    print(f"Evaluated {len(rows)} tasks → docs/evaluations/{DATE}-pipeline.{{json,md}}")
    print("  verdicts:", out["verdicts"], "| overall:", out["overall"])
    for g in gaps:
        print("  GAP:", g)


if __name__ == "__main__":
    main()
