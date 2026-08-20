#!/usr/bin/env python3
"""S3 knowledge-loop eval panel — the context engine's own wiring.

Consistency of the knowledge base (docs/knowledge/) — the context engine's spine:

  K1 index-link integrity   — every link in docs/knowledge/index.md resolves
      (file exists, optional #anchor exists in target).
  K2 session evidence       — every decision file has its session.jsonl sibling
      (decisions are backed by full-session evidence for drift-off evals).
  K3 index coverage         — every decision file under sessions/ is linked from
      index.md (no orphaned knowledge; the engine can find every decision).

Emits docs/evaluations/<date>-knowledge.{json,md} + best-effort Langfuse scores.

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
KNOW = os.path.join(WS, "docs", "knowledge")
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


# ── K1: index-link integrity ────────────────────────────────────────────────
def _gfm_slug(h):
    """GitHub-Flavoured-Markdown heading slug: lowercase, strip punctuation,
    spaces -> hyphens. (Keeps a leading number prefix; strips the trailing dot.)"""
    import unicodedata
    h = unicodedata.normalize('NFKD', h).lower()
    h = re.sub(r'[^\w\- ]', '', h)
    return h.replace(' ', '-')


def index_links():
    idx = read(os.path.join(KNOW, "index.md"))
    links = re.findall(r"\]\((sessions/[^)#]+\.md(?:#[^)]+)?)\)", idx)
    rows, broken = [], []
    for link in links:
        path, _, anchor = link.partition("#")
        ok = _fexists("docs", "knowledge", path)
        if ok and anchor:
            tgt = read(os.path.join(KNOW, path))
            # anchor resolves if the file has a heading whose GFM slug == anchor,
            # OR a verbatim #anchor exists
            heads = re.findall(r'^#{1,6}\s+(.+)$', tgt, re.M)
            ok = (f"#{anchor}" in tgt) or any(_gfm_slug(h) == anchor for h in heads)
        rows.append({"link": link, "pass": ok})
        if not ok:
            broken.append(link)
    return rows, broken


# ── K2: decision → session.jsonl evidence ───────────────────────────────────
def session_evidence():
    rows, missing = [], []
    for sess in sorted(os.listdir(os.path.join(KNOW, "sessions"))):
        dec_dir = os.path.join(KNOW, "sessions", sess, "decisions")
        if not os.path.isdir(dec_dir):
            continue
        sess_ok = _fexists("docs", "knowledge", "sessions", sess, "session.jsonl")
        for f in sorted(os.listdir(dec_dir)):
            if f.endswith(".md"):
                rows.append({"decision": f"{sess}/{f}", "session": sess, "ok": sess_ok})
                if not sess_ok:
                    missing.append(f"{sess}/session.jsonl (decision {f})")
    return rows, missing


# ── K3: index coverage (every decision indexed) ─────────────────────────────
def index_coverage():
    idx = read(os.path.join(KNOW, "index.md"))
    rows, unindexed = [], []
    for sess in sorted(os.listdir(os.path.join(KNOW, "sessions"))):
        dec_dir = os.path.join(KNOW, "sessions", sess, "decisions")
        if not os.path.isdir(dec_dir):
            continue
        for f in sorted(os.listdir(dec_dir)):
            if not f.endswith(".md"):
                continue
            rel = f"sessions/{sess}/decisions/{f}"
            linked = rel in idx
            rows.append({"decision": rel, "linked": linked})
            if not linked:
                unindexed.append(rel)
    return rows, unindexed


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
    idx, idx_broken = index_links()
    sess_rows, sess_missing = session_evidence()
    cov_rows, unindexed = index_coverage()

    checks = {
        "K1-index-links": {"total": len(idx), "broken": idx_broken,
                           "pass": not idx_broken},
        "K2-session-evidence": {"total": len(sess_rows), "missing": sess_missing,
                                "pass": not sess_missing},
        "K3-index-coverage": {"decisions": len(cov_rows), "unindexed": unindexed,
                              "pass": not unindexed},
    }
    gaps = (["K1 broken link: " + b for b in idx_broken]
            + ["K2 missing evidence: " + m for m in sess_missing]
            + ["K3 unindexed: " + u for u in unindexed])
    failures = [c for c, v in checks.items() if not v["pass"]]

    out = {"generated": DATE, "checks": checks, "gaps": gaps,
           "verdict": "FAIL" if failures else "PASS"}

    os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-knowledge.json"), "w") as f:
        json.dump(out, f, indent=2)

    md = [f"# Knowledge-Loop Evaluation — {DATE}", "",
          f"Verdict: **{out['verdict']}** · "
          f"K1 {len(idx)} links · K2 {len(sess_rows)} decisions · K3 {len(cov_rows)} decisions", "",
          "## Checks", "",
          "| check | total | broken/missing/unindexed | verdict |", "|---|---|---|---|"]
    md.append("| K1 index links | {} | {} | {} |".format(len(idx), len(idx_broken),
                                                        "PASS" if not idx_broken else "FAIL"))
    md.append("| K2 session evidence | {} | {} | {} |".format(len(sess_rows), len(sess_missing),
                                                             "PASS" if not sess_missing else "FAIL"))
    md.append("| K3 index coverage | {} | {} | {} |".format(len(cov_rows), len(unindexed),
                                                           "PASS" if not unindexed else "FAIL"))
    md += ["", "## Gaps", ""]
    md += [f"- {g}" for g in (gaps or ["(none)"])]
    md += ["", f"_JSON: docs/evaluations/{DATE}-knowledge.json_", ""]
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-knowledge.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    lf = LF()
    tid = lf.latest_trace()
    if tid:
        ok = lf.post_score(tid, "factory:knowledge-loop", 1.0 if not failures else 0.0,
                           "; ".join(gaps) or "all knowledge checks pass")
        print(f"  SCORE knowledge-loop: {tid} value={'1.0' if not failures else '0.0'} "
              f"{'posted' if ok else 'FAILED'}")

    print(f"Evaluated S3 knowledge loop → docs/evaluations/{DATE}-knowledge.{{json,md}}")
    print("  verdict:", out["verdict"])
    for g in gaps:
        print("  GAP:", g)


if __name__ == "__main__":
    main()
