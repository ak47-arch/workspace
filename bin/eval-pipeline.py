#!/usr/bin/env python3
"""eval-pipeline.py — first evaluation pass over the factory dataset.

Joins tasks ↔ PR tracking (dec 06) ↔ implementations ↔ code-reviews ↔ session
traces and emits a metrics report under docs/evaluations/<date>-pipeline.{json,md}
plus a schema-gap list (what the data is missing — the backlog for the next
automation round).

Usage: python3 bin/eval-pipeline.py
"""
import glob, json, os, re, sys
from datetime import datetime

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATE = datetime.now().strftime("%Y-%m-%d")


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""


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


rows, gaps = [], []
for task_file in sorted(glob.glob(os.path.join(WS, "docs/tasks", "*.md"))):
    slug = os.path.splitext(os.path.basename(task_file))[0]
    if slug == "README":
        continue  # docs/tasks/README.md is documentation, not a task
    t = read(task_file)
    m = re.search(r"^\*\*Status\*\*:\s*(\S+)", t, re.M)
    status = m.group(1) if m else "?"
    pr = re.search(r"^- PR: #(\d+) \((\S+)\)", t, re.M)
    url = re.search(r"^- URL: (\S+)", t, re.M)
    raised = re.search(r"^- Raised by: implementer run ([0-9a-f-]{8,})", t, re.M)
    review = re.search(r"^- Review: session ([0-9a-f-]{8,}) · verdict (\S+)", t, re.M)
    merge = re.search(r"^- Merge: (\S+)", t, re.M)
    if not (pr or review or merge):
        gaps.append(f"task {slug}: no PR tracking section (dec 06)")

    impl_reps = glob.glob(os.path.join(WS, "docs/implementations", f"*-{slug}", "report.md"))
    rev_reps = glob.glob(os.path.join(WS, "docs/code-reviews", f"*-{slug}", "report.md"))
    i_text = read(impl_reps[0]) if impl_reps else ""
    r_text = read(rev_reps[0]) if rev_reps else ""
    if not impl_reps:
        gaps.append(f"task {slug}: no implementation report archived")
    if not rev_reps:
        gaps.append(f"task {slug}: no code-review report (pre-reviewer era?)")

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

    rows.append({
        "task": slug, "status": status,
        "pr": f"#{pr.group(1)}" if pr else None,
        "repo": pr.group(2) if pr else None,
        "url": url.group(1) if url else None,
        "raised_by": raised_uuid, "raised_first_ts": r0, "raised_last_ts": r1,
        "review_session": review_uuid, "verdict": verdict,
        "review_first_ts": v0, "review_last_ts": v1,
        "merge_sha": merge.group(1) if merge else None,
        "impl_stories": impl_stories,
        "stories_pass": stories_pass, "stories_fail": stories_fail,
        "blocking_findings": blocking, "advisory_findings": advisory,
    })

out = {"generated": DATE, "tasks": rows, "schema_gaps": gaps}
os.makedirs(os.path.join(WS, "docs/evaluations"), exist_ok=True)
with open(os.path.join(WS, "docs/evaluations", f"{DATE}-pipeline.json"), "w") as f:
    json.dump(out, f, indent=2)

# Markdown summary.
md = [f"# Pipeline Evaluation — {DATE}", "",
      "| task | status | PR | verdict | stories (P/F) | blocking | advisory | merge |",
      "|---|---|---|---|---|---|---|---|"]
for r in rows:
    md.append("| {task} | {status} | {pr} | {verdict} | {sp}/{sf} | {b} | {a} | {m} |".format(
        task=r["task"], status=r["status"], pr=r["pr"] or "—",
        verdict=(r["verdict"][:40] if r["verdict"] else "—"),
        sp=r["stories_pass"], sf=r["stories_fail"],
        b=r["blocking_findings"], a=r["advisory_findings"],
        m=(r["merge_sha"][:8] if r["merge_sha"] else "—")))
verdicts = {}
for r in rows:
    v = "APPROVE" if "APPROVE" in r["verdict"] else ("REQUEST_CHANGES" if "REQUEST_CHANGES" in r["verdict"] else "other")
    verdicts[v] = verdicts.get(v, 0) + 1
md += ["", "## Verdict distribution", ""]
for k, v in sorted(verdicts.items()):
    md.append(f"- {k}: {v}")
md += ["", "## Schema gaps (evaluation-data backlog)", ""]
for g in (gaps or ["(none)"]) :
    md.append(f"- {g}")
md += ["", f"_JSON: docs/evaluations/{DATE}-pipeline.json_", ""]
with open(os.path.join(WS, "docs/evaluations", f"{DATE}-pipeline.md"), "w") as f:
    f.write("\n".join(md) + "\n")

print(f"Evaluated {len(rows)} tasks → docs/evaluations/{DATE}-pipeline.{{json,md}}")
for g in gaps:
    print(f"  GAP: {g}")
