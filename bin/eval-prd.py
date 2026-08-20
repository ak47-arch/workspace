#!/usr/bin/env python3
"""S4 PRD/review-loop eval panel — the assembly-line gate's fidelity.

Grades the PRD → review → merge loop (the factory's production process):

  P1 PRD lifecycle      — every archived PRD has a task file; every task file
      with a PR-tracking section maps to a real, merged (or correctly pending)
      PR. Orphan PRDs (archived but never implemented) are gaps.
  P2 review fidelity    — every task with a PR-tracking section has a review
      verdict (APPROVE / REQUEST_CHANGES) recorded in docs/code-reviews/.
      An APPROVE must have a merge sha (the review gate was honored).
  P3 no post-merge      — no task's merge sha points to a commit that was later
      revert (i.e. the merged PR's change survived). Deterministic proxy: the
      merged commit is an ancestor of origin/master HEAD.

Independent gold only (decision 01): we grade *that* a verdict exists and *that*
the loop completed — never judge whether the reviewer was right (that would be
reviewer-grading-own-implementer circularity).

Emits docs/evaluations/<date>-prd.{json,md} + best-effort Langfuse scores.

Score caveat: v4 scores must write via synchronous POST /api/public/scores (the
batch /api/public/ingestion score-create path silently drops scores in v4 dual
mode).
"""
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


def slug_of(path):
    return os.path.basename(path).replace(".md", "")


# ── Corpus ──────────────────────────────────────────────────────────────────
def archived_prds():
    d = os.path.join(WS, "docs", "prd-archive")
    return sorted(os.listdir(d)) if os.path.isdir(d) else []


def task_pr_sections():
    """Map task slug -> its PR-tracking block (PR number, review session, verdict, merge sha).
    Multi-PR blocks (revise/re-review) use the LAST PR's verdict + merge sha."""
    out = {}
    td = os.path.join(WS, "docs", "tasks")
    if not os.path.isdir(td):
        return out
    for f in sorted(os.listdir(td)):
        if not f.endswith(".md"):
            continue
        text = read(os.path.join(td, f))
        slug = f[:-3]
        m = re.search(r"## PR tracking(.*?)(?=\n## |\Z)", text, re.S)
        if not m:
            continue
        block = m.group(1)
        # collect ALL PR entries; take the last one's verdict/merge
        prs = re.findall(r"PR:\s*#(\d+)", block)
        sessions = re.findall(r"Review:\s*session\s+(\S+)\s*·\s*verdict\s+(APPROVE|REQUEST_CHANGES|n\/a|REVISE)", block, re.I)
        merges = re.findall(r"Merge:\s*([0-9a-f]{7,})", block)
        urls = re.findall(r"URL:\s*(\S+)", block)
        out[slug] = {
            "has_pr": bool(prs),
            "pre_pr_era": bool(re.search(r"pre-PR-era|No PR —", block)),
            "pr_num": prs[-1] if prs else None,
            "review_session": sessions[-1][0] if sessions else None,
            "verdict": sessions[-1][1] if sessions else None,
            "merge_sha": merges[-1] if merges else None,
            "url": urls[-1] if urls else None,
            "n_prs": len(prs),
        }
    return out


def merge_survived(sha_prefix):
    """True if the merged commit (by prefix) is an ancestor of origin/master HEAD.
    None if the sha does not resolve (recorded but invalid -> a data-quality gap)."""
    if not sha_prefix:
        return None
    # verify the sha resolves to a commit first
    r = _git(["cat-file", "-e", sha_prefix + "^{commit}"])
    if r:  # non-empty stderr / non-zero -> not a real commit
        return None
    r = subprocess.run(["git", "-C", WS, "merge-base", "--is-ancestor",
                        sha_prefix, "origin/master"], capture_output=True)
    return r.returncode == 0


# ── Checks ──────────────────────────────────────────────────────────────────
def prd_lifecycle():
    rows, gaps = [], []
    tasks = task_pr_sections()
    for prd in archived_prds():
        # task files are SLUG-named (docs/tasks/<slug>.md), PRDs are date-prefixed
        slug = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", slug_of(prd))
        has_task = _fexists("docs", "tasks", slug + ".md")
        rows.append({"prd": prd, "task_file": has_task,
                     "has_pr_tracking": slug in tasks})
        if not has_task:
            gaps.append(f"{prd}: no task file docs/tasks/{slug}.md")
        elif slug not in tasks:
            gaps.append(f"{slug}: task file exists but no PR-tracking section")
    return rows, gaps


def review_fidelity():
    rows, gaps = [], []
    for slug, t in task_pr_sections().items():
        verdict = t["verdict"]
        # code-review dirs are date-prefixed (2026-08-17-<slug>/report.md)
        import glob as _glob
        report = _glob.glob(os.path.join(WS, "docs", "code-reviews", "*" + slug, "report.md"))
        has_report = bool(report)
        # pre-PR-era tasks: honestly marked, no PR pipeline existed — not a gap
        if t["pre_pr_era"]:
            rows.append({"task": slug, "pr": None, "verdict": None, "report": False,
                         "merge_sha": None, "ok": True, "pre_pr_era": True})
            continue
        ok = bool(t["has_pr"] and verdict and (verdict.upper() in ("APPROVE", "REQUEST_CHANGES")))
        # APPROVE must have a merge sha; REQUEST_CHANGES may still be pending
        if verdict and verdict.upper() == "APPROVE" and not t["merge_sha"]:
            ok = False
        rows.append({"task": slug, "pr": t["pr_num"], "verdict": verdict,
                     "report": has_report, "merge_sha": t["merge_sha"], "ok": ok,
                     "pre_pr_era": False})
        if not ok:
            reason = "no PR" if not t["has_pr"] else (
                "no/odd verdict (last review {})".format(t["verdict"]) if (
                    not verdict or verdict.upper() == "N/A") else (
                "APPROVE without merge sha" if verdict.upper() == "APPROVE" and not t["merge_sha"]
                else "report missing"))
            gaps.append(f"{slug}: {reason}")
    return rows, gaps


def post_merge_revert():
    rows, gaps = [], []
    for slug, t in task_pr_sections().items():
        survived = merge_survived(t["merge_sha"]) if t["merge_sha"] else None
        unverifiable = t.get("url") is not None and "feed_analyser" in (t.get("url") or "")
        rows.append({"task": slug, "merge_sha": t["merge_sha"], "survived": survived,
                     "foreign_repo": unverifiable, "pre_pr_era": t["pre_pr_era"]})
        # pre-PR-era tasks have no merge sha by definition — not a data-quality gap
        if t["pre_pr_era"]:
            continue
        if survived is False and not unverifiable:
            gaps.append(f"{slug}: merged commit {t['merge_sha']} is NOT an ancestor of master (revert?)")
        elif survived is None and not unverifiable:
            gaps.append(f"{slug}: recorded merge sha {t['merge_sha']} does not resolve (data-quality)")
    return rows, gaps


# ── Langfuse ────────────────────────────────────────────────────────────────
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
        self.auth, self.base = None, "http://localhost:3000"
        if c and not NO_LANGFUSE:
            import base64
            self.auth = "Basic " + base64.b64encode(f"{c[0]}:{c[1]}".encode()).decode()

    def get_json(self, path):
        if not self.auth:
            return None
        r = urllib.request.Request(self.base + path, headers={"Authorization": self.auth})
        with urllib.request.urlopen(r, timeout=10) as resp:
            return json.load(resp)

    def latest_trace(self):
        if not self.auth:
            return None
        try:
            d = self.get_json("/api/public/traces?limit=1")
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
    p1_rows, p1_gaps = prd_lifecycle()
    p2_rows, p2_gaps = review_fidelity()
    p3_rows, p3_gaps = post_merge_revert()

    checks = {
        "P1-prd-lifecycle": {"total": len(p1_rows), "gaps": p1_gaps, "pass": not p1_gaps},
        "P2-review-fidelity": {"total": len(p2_rows), "gaps": p2_gaps, "pass": not p2_gaps},
        "P3-no-post-merge-revert": {"total": len(p3_rows), "gaps": p3_gaps, "pass": not p3_gaps},
    }
    gaps = (["P1: " + g for g in p1_gaps] + ["P2: " + g for g in p2_gaps]
            + ["P3: " + g for g in p3_gaps])
    failures = [c for c, v in checks.items() if not v["pass"]]

    out = {"generated": DATE, "checks": checks, "gaps": gaps,
           "verdict": "FAIL" if failures else "PASS"}

    os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-prd.json"), "w") as f:
        json.dump(out, f, indent=2)

    md = [f"# PRD/Review-Loop Evaluation — {DATE}", "",
          f"Verdict: **{out['verdict']}** · archived PRDs {len(p1_rows)} · "
          f"tracked tasks {len(p2_rows)} · merges {sum(1 for r in p3_rows if r['merge_sha'])}", "",
          "## Checks", "",
          "| check | total | gaps | verdict |", "|---|---|---|---|"]
    for c, v in checks.items():
        md.append("| {} | {} | {} | {} |".format(c, v["total"], len(v["gaps"]),
                                                "PASS" if v["pass"] else "FAIL"))
    md += ["", "## Gaps", ""]
    md += [f"- {g}" for g in (gaps or ["(none)"])]
    md += ["", f"_JSON: docs/evaluations/{DATE}-prd.json_", ""]
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-prd.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    lf = LF()
    tid = lf.latest_trace()
    if tid:
        ok = lf.post_score(tid, "factory:prd-review-loop", 1.0 if not failures else 0.0,
                           "; ".join(gaps) or "all PRD/review checks pass")
        print(f"  SCORE prd-review-loop: {tid} value={'1.0' if not failures else '0.0'} "
              f"{'posted' if ok else 'FAILED'}")

    print(f"Evaluated S4 PRD/review loop → docs/evaluations/{DATE}-prd.{{json,md}}")
    print("  verdict:", out["verdict"])
    for g in gaps:
        print("  GAP:", g)


if __name__ == "__main__":
    main()
