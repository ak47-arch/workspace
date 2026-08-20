#!/usr/bin/env python3
"""S7 context-engine eval panel (breadth-first surface expansion).

The decision-03 headline surface: grade the factory's OWN context engine — the
progressive-disclosure spine (AGENTS.md → factory-context.md → discovery layer
→ knowledge base) that every downstream component consumes.  Three check
classes, all deterministic:

  C1 footprint/leanness — the always-loaded + first-discovery context stays
     lean.  AGENTS.md (auto-injected) and factory-context.md (first discovery
     doc) must stay within token budgets; a persistent baseline (context.json)
     flags >2x growth so leanness is a trend, not a snapshot.

  C2 retrieval reachability — the spine docs' pointer network resolves: every
     relative markdown link in factory-context.md / openwiki/index.md /
     docs/evaluations/{README,surfaces}.md points at an existing file (GFM
     anchor aware).  Broken links = context an agent cannot retrieve.

  C3 summary fidelity — the context doc's structural claims match artifacts:
     "five components" (5 component definitions), roster table rows ↔ agent
     files, projects-table vision links resolve, and the "initial context
     footprint ~2,500 tokens" claim is not exceeded by AGENTS.md alone.

Emits docs/evaluations/<date>-context.{json,md} + a persistent trend store
docs/evaluations/context.json, and a fleet-level Langfuse score (synchronous
POST /api/public/scores — batch ingestion silently drops scores in v4 dual
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


def est_tokens(text):
    """Deterministic heuristic: ~4 chars/token (English prose)."""
    return max(1, len(text) // 4)


# ── C1 footprint / leanness ─────────────────────────────────────────────────
FOOTPRINT_FILES = [
    # (rel path, budget tokens, role)
    ("AGENTS.md", 1000, "always-injected (auto-loaded)"),
    ("docs/factory-context.md", 4000, "first discovery doc (on demand)"),
    ("docs/knowledge/index.md", 8000, "deep layer entry (last resort)"),
]
INITIAL_FOOTPRINT_CLAIM = 2500  # factory-context.md: "~2,500 tokens"


def footprint_checks(prev):
    rows, fails, advisories = [], [], []
    for rel, budget, role in FOOTPRINT_FILES:
        tok = est_tokens(read(os.path.join(WS, rel)))
        ok = tok <= budget
        prior = (prev or {}).get(rel, {}).get("tokens")
        grew = prior is not None and tok > 2 * prior
        rows.append({"item": rel, "role": role, "est_tokens": tok,
                     "budget": budget, "pass": ok, "grew_2x": bool(grew)})
        if not ok:
            fails.append(f"{rel}: est {tok} tok exceeds {budget} budget")
        elif grew:
            advisories.append(f"{rel}: est {tok} tok vs prior {prior} — grew >2x, re-check leanness")

    # initial-footprint claim: AGENTS.md alone must be a minor part of the claim
    agents = est_tokens(read(os.path.join(WS, "AGENTS.md")))
    claim_ok = agents <= INITIAL_FOOTPRINT_CLAIM // 2
    rows.append({"item": "AGENTS.md vs initial-footprint claim",
                 "role": "claim (~{}) sanity".format(INITIAL_FOOTPRINT_CLAIM),
                 "est_tokens": agents,
                 "budget": INITIAL_FOOTPRINT_CLAIM // 2,
                 "pass": claim_ok, "grew_2x": False})
    if not claim_ok:
        fails.append(f"AGENTS.md alone ({agents} tok) exceeds half the ~{INITIAL_FOOTPRINT_CLAIM} claim")

    return rows, fails, advisories


# ── C2 retrieval reachability (spine-doc link integrity) ───────────────────
SPINE_DOCS = [
    "docs/factory-context.md",
    "docs/evaluations/README.md",
    "docs/evaluations/surfaces.md",
    "openwiki/index.md",
]


def gfm_anchor_slug(heading):
    """GFM slug: lowercase, strip non-alnum, spaces → '-'. '## 1. Knowledge…' → '1-knowledge…'."""
    slug = heading.lower().strip()
    slug = re.sub(r"[^a-z0-9\s-]", "", slug)
    slug = re.sub(r"\s+", "-", slug)
    return slug


def doc_anchors(path):
    body = read(path)
    return {gfm_anchor_slug(h): True for h in
            re.findall(r"^#{1,6}\s+(.+)$", body, re.M)}


def reachability_checks():
    rows, fails = [], []
    for doc in SPINE_DOCS:
        path = os.path.join(WS, doc)
        if not os.path.isfile(path):
            rows.append({"doc": doc, "links": 0, "broken": 0, "pass": False})
            fails.append(f"{doc}: spine doc missing")
            continue
        text = read(path)
        base = os.path.dirname(path)
        anchors = doc_anchors(path)
        total = broken = 0
        broken_targets = []
        for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
            target = m.group(1).strip()
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            total += 1
            path_part = target.split("#", 1)[0]
            anchor_part = target.split("#", 1)[1] if "#" in target else None
            if path_part:
                full = os.path.normpath(os.path.join(base, path_part))
                if not os.path.exists(full):
                    broken += 1
                    broken_targets.append(target)
                    continue
                if anchor_part:
                    src_anchors = doc_anchors(full)
                else:
                    continue
            else:
                src_anchors = anchors
            if anchor_part and anchor_part not in src_anchors:
                broken += 1
                broken_targets.append(target + " (anchor)")
        ok = broken == 0
        rows.append({"doc": doc, "links": total, "broken": broken, "pass": ok})
        if not ok:
            fails.append("{}: {} of {} links unresolvable: {}".format(
                doc, broken, total, "; ".join(broken_targets[:5])))
    return rows, fails


# ── C3 summary fidelity ─────────────────────────────────────────────────────
def fidelity_checks():
    rows, fails = [], []
    ctx = read(os.path.join(WS, "docs", "factory-context.md"))

    # five components claim
    comps = re.findall(r"^\*\*([a-z_/]+)\*\* — ", ctx, re.M)
    five = len(comps) == 5
    rows.append({"claim": "five components", "observed": str(len(comps)),
                 "pass": five})
    if not five:
        fails.append("factory-context claims 'five components' but found {}: {}".format(
            len(comps), ", ".join(comps)))

    # roster table rows ↔ agent files
    roster = re.findall(r"^\| \*\*([a-z-]+)\*\* \|", ctx, re.M)
    roster_ok = all(_fexists(".pi", "agents", name + ".md") for name in roster)
    rows.append({"claim": "roster table ↔ agent files",
                 "observed": "{} rows, all files exist".format(len(roster))
                 if roster_ok else "{} rows, MISSING files".format(len(roster)),
                 "pass": roster_ok})
    if not roster_ok:
        fails.append("roster table lists agents without .pi/agents/<name>.md: "
                     + ", ".join(n for n in roster if not _fexists(".pi", "agents", n + ".md")))

    # projects table vision links resolve
    missing_visions = []
    for m in re.finditer(r"\(\.\./([^)]*VISION\.md)\)", ctx):
        rel = m.group(1)
        if not _fexists(rel):
            missing_visions.append(rel)
    vis_ok = not missing_visions
    rows.append({"claim": "projects-table vision links resolve",
                 "observed": "0 missing" if vis_ok
                 else "missing: " + ", ".join(missing_visions),
                 "pass": vis_ok})
    if not vis_ok:
        fails.append("projects table vision links broken: " + ", ".join(missing_visions))

    # initial footprint claim sanity (AGENTS.md within claim)
    agents = est_tokens(read(os.path.join(WS, "AGENTS.md")))
    claim_ok = agents <= 1000
    rows.append({"claim": "AGENTS.md within initial-footprint claim (~2,500 tok)",
                 "observed": "{} est tok".format(agents), "pass": claim_ok})
    if not claim_ok:
        fails.append("AGENTS.md est {} tok — the '~2,500 tok initial footprint' claim is stale".format(agents))

    return rows, fails


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
    # persistent trend store (leanness baseline across runs)
    pf = os.path.join(WS, "docs", "evaluations", "context.json")
    prev = {}
    if os.path.isfile(pf):
        try:
            prev = json.load(open(pf))
        except Exception:
            prev = {}

    fp_rows, fp_fails, fp_adv = footprint_checks(prev.get("footprint", {}))
    reach_rows, reach_fails = reachability_checks()
    fid_rows, fid_fails = fidelity_checks()

    fails = fp_fails + reach_fails + fid_fails
    verdict = "FAIL" if fails else "PASS"

    out = {
        "generated": DATE,
        "verdict": verdict,
        "failures": fails,
        "advisories": fp_adv,
        "footprint": fp_rows,
        "reachability": reach_rows,
        "fidelity": fid_rows,
    }
    os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-context.json"), "w") as f:
        json.dump(out, f, indent=2)

    # update trend store (record today's footprint baselines)
    prev["footprint"] = {r["item"]: {"tokens": r["est_tokens"], "date": DATE}
                         for r in fp_rows}
    prev["last_run"] = DATE
    with open(pf, "w") as f:
        json.dump(prev, f, indent=2)

    md = [f"# Context-Engine Evaluation (S7) — {DATE}",
          f"Verdict: **{verdict}**", "",
          "## C1 — Footprint / leanness", "",
          "| item | role | est tokens | budget | verdict |", "|---|---|---|---|---|"]
    for r in fp_rows:
        flag = "FAIL" if not r["pass"] else ("⚠ grew 2x" if r["grew_2x"] else "PASS")
        md.append("| {} | {} | {} | {} | {} |".format(
            r["item"], r["role"], r["est_tokens"], r["budget"], flag))
    md += ["", "## C2 — Retrieval reachability (spine link integrity)", "",
           "| doc | links | broken | verdict |", "|---|---|---|---|"]
    for r in reach_rows:
        md.append("| {} | {} | {} | {} |".format(
            r["doc"], r["links"], r["broken"], "PASS" if r["pass"] else "FAIL"))
    md += ["", "## C3 — Summary fidelity", "",
           "| claim | observed | verdict |", "|---|---|---|"]
    for r in fid_rows:
        md.append("| {} | {} | {} |".format(
            r["claim"], r["observed"], "PASS" if r["pass"] else "FAIL"))
    md += ["", "## Failures", ""]
    md += [f"- {f}" for f in fails or ["(none)"]]
    md += ["", "## Advisories", ""]
    md += [f"- {a}" for a in fp_adv or ["(none)"]]
    md += ["", f"_JSON: docs/evaluations/{DATE}-context.json · trend: context.json_", ""]
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-context.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    lf = LF()
    tid = lf.latest_trace()
    if tid:
        ok = lf.post_score(tid, "factory:S7-context-engine", 1.0 if verdict == "PASS" else 0.0,
                           "; ".join(fails) or "context engine lean, reachable, faithful")
        print(f"  SCORE factory:S7-context-engine: {tid} value={'1.0' if verdict=='PASS' else '0.0'} "
              f"{'posted' if ok else 'FAILED'}")

    print("Evaluated S7 context-engine → docs/evaluations/{}-context.{{json,md}}".format(DATE))
    print("  verdict: " + verdict + (" (0 gaps)" if not fails else " → " + "; ".join(fails)))


if __name__ == "__main__":
    main()
