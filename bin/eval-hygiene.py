#!/usr/bin/env python3
"""S8 roster-completeness + S9 repo-hygiene eval panel (breadth-first surface expansion).

Deterministic checks over the factory's OWN governance invariants:

  S8 roster-completeness — every roster agent (factory-context roster) has the
     complete contract triad: persona (.pi/agents/<name>.md), run-contract
     (.agents/skills/<contract>/SKILL.md), artifact map (docs/reference/<ref>.md).

  S9 repo-hygiene — master merge-only (PR merge commits dominate; branch
     protection present), `opensource/` gitignored, `.env.*` secrets ignored,
     no secret VALUES in tracked files.

Emits docs/evaluations/<date>-hygiene.{json,md} + best-effort Langfuse scores
(fleet-level: posted to the latest trace as the standing health readout).

Score caveat: v4 scores must write via synchronous POST /api/public/scores —
the batch /api/public/ingestion score-create path silently drops scores in
v4 dual mode.
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


def _git_ignored(rel):
    r = subprocess.run(["git", "-C", WS, "check-ignore", "-q", rel],
                       capture_output=True)
    return r.returncode == 0


def _git(args):
    r = subprocess.run(["git", "-C", WS] + args, capture_output=True, text=True)
    return (r.stdout or "").strip()


# ── S8 roster (from docs/factory-context.md roster) ─────────────────────────
# (agent name, run-contract skill dir, reference map filename)
ROSTER = [
    ("prd-reviewer", None, None),          # persona only today — contract triad gap
    ("implementer", "implementer-ops", "implementer-agent.md"),
    ("code-reviewer", "review-ops", "reviewer-agent.md"),
    ("evaluator", "eval-ops", "evaluator-agent.md"),
]


def roster_checks():
    rows, fails = [], []
    for name, skill, ref in ROSTER:
        checks = [
            {"check": "persona (.pi/agents/{}.md)".format(name),
             "pass": _fexists(".pi", "agents", name + ".md")},
            {"check": "run-contract (.agents/skills/{}/SKILL.md)".format(skill or "«none»"),
             "pass": bool(skill) and _fexists(".agents", "skills", skill, "SKILL.md")},
            {"check": "artifact map (docs/reference/{})".format(ref or "«none»"),
             "pass": bool(ref) and _fexists("docs", "reference", ref)},
        ]
        ok = all(c["pass"] for c in checks)
        rows.append({"agent": name, "checks": checks, "pass": ok})
        if not ok:
            fails.append(name + ": " + "; ".join(
                c["check"] for c in checks if not c["pass"]))
    return rows, fails


# ── S9 repo-hygiene ─────────────────────────────────────────────────────────
def _secret_value_hits():
    """Scan tracked files for REAL secret values — provider-prefixed keys only.
    Provider keys carry a distinctive prefix (sk-or-v1, sk-ant, sk-proj, pk-lf,
    sk-lf, sk-svcacct); a bare 40-char hex is a git SHA, base64 is session
    content — neither is a key shape. Test stubs (sk-test, sk-*-test-*,
    $KEY) are excluded — they are placeholders, not leaks.
    Returns redacted evidence (first 8 chars + ellipsis) so the report JSON
    never persists an actual key."""
    stub_words = ("test", "example", "dummy", "placeholder", "override")

    def is_stub(val):
        low = val.lower()
        return any(w in low for w in stub_words) or len(val) < 24

    def redact(val):
        body = val.split("=", 1)[-1] if "=" in val else val
        return body[:8] + "…"

    hits = []
    tracked = _git(["ls-files"]).splitlines()
    # matches provider-prefixed keys (OpenRouter / Anthropic / OpenAI / langfuse)
    key_re = re.compile(
        r"(sk-(?:or-v1|ant|proj|svcacct|user)-[A-Za-z0-9_\-]{10,}|"
        r"(?:pk|sk)-lf-[A-Za-z0-9_\-]{10,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"
        r"(?:LANGFUSE|OPENROUTER)_(?:SECRET|API)_KEY\s*=\s*sk-[A-Za-z0-9_\-]{10,})")
    for rel in tracked:
        text = read(os.path.join(WS, rel))
        for m in key_re.finditer(text):
            val = m.group(0)
            body = val.split("=", 1)[-1] if "=" in val else val
            if "PRIVATE KEY-----" in body and not body.endswith("-----"):
                continue
            if is_stub(body):
                continue
            hits.append("{}: {}".format(rel, redact(val)))
    return hits


def hygiene_checks():
    rows, fails = [], []

    # master merge-only — merge commits dominate recent history + protection exists
    recent = _git(["log", "origin/master", "--oneline", "--merges", "-20"])
    merge_share = len(recent.splitlines()) / 20.0 if recent else 0.0
    merge_only = merge_share >= 0.9
    rows.append({"check": "master merge-only (recent history ≈ PR merges)",
                 "pass": merge_only, "evidence": "{} of last 20 commits are merges".format(
                     len(recent.splitlines()))})
    if not merge_only:
        fails.append("master history not merge-dominated")

    # branch protection present (PR-based landing enforced at GitHub)
    prot = _git(["config", "--get", "remote.origin.url"]) and _gh_protection()
    rows.append({"check": "branch protection on master (gh api)",
                 "pass": prot, "evidence": "required_pull_request_reviews present" if prot
                 else "gh api returned no protection"})
    if not prot:
        fails.append("no branch protection on master")

    # opensource/ gitignored (official skills live outside the repo)
    os_ignored = _git_ignored("opensource/langfuse")
    rows.append({"check": "opensource/ gitignored",
                 "pass": os_ignored, "evidence": "git check-ignore opensource/langfuse"})
    if not os_ignored:
        fails.append("opensource/ not gitignored")

    # .env secrets ignored
    env_ignored = _git_ignored(".env.langfuse") and ".env.*" in read(
        os.path.join(WS, ".gitignore"))
    rows.append({"check": ".env.* secrets ignored",
                 "pass": env_ignored, "evidence": ".gitignore has .env.*; check-ignore ok"})
    if not env_ignored:
        fails.append(".env secrets not ignored")

    # no secret VALUES in tracked files
    hits = _secret_value_hits()
    rows.append({"check": "no secret values in tracked files",
                 "pass": not hits, "evidence": str(len(hits)) + " hit(s)"})
    if hits:
        fails.append("secrets in tracked files: " + "; ".join(h[:60] for h in hits))

    return rows, fails


def _gh_protection():
    r = subprocess.run(["gh", "api", "repos/ak47-arch/workspace/branches/master/protection"],
                       capture_output=True, text=True)
    return r.returncode == 0 and "required_pull_request_reviews" in (r.stdout or "")


# ── Langfuse (fleet-level scores on the latest trace) ───────────────────────
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
    roster, roster_fails = roster_checks()
    hygiene, hygiene_fails = hygiene_checks()

    out = {
        "generated": DATE,
        "surfaces": {
            "S8-roster-completeness": {
                "rows": roster,
                "failures": roster_fails,
                "verdict": "FAIL" if roster_fails else "PASS",
            },
            "S9-repo-hygiene": {
                "rows": hygiene,
                "failures": hygiene_fails,
                "verdict": "FAIL" if hygiene_fails else "PASS",
            },
        },
    }

    os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-hygiene.json"), "w") as f:
        json.dump(out, f, indent=2)

    md = [f"# Factory Hygiene Evaluation — {DATE}", "",
          "## S8 — Roster completeness", "",
          "| agent | checks | verdict |", "|---|---|---|"]
    for r in roster:
        detail = "; ".join("✓" if c["pass"] else "✗ " + c["check"]
                           for c in r["checks"])
        md.append("| {} | {} | {} |".format(
            r["agent"], detail, "PASS" if r["pass"] else "FAIL"))
    md += ["", "## S9 — Repo hygiene", "",
           "| check | verdict | evidence |", "|---|---|---|"]
    for h in hygiene:
        md.append("| {} | {} | {} |".format(
            h["check"], "PASS" if h["pass"] else "FAIL", h["evidence"]))
    md += ["", "## Failures", ""]
    md += [f"- {f}" for f in (roster_fails + hygiene_fails) or ["(none)"]]
    md += ["", f"_JSON: docs/evaluations/{DATE}-hygiene.json_", ""]
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-hygiene.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    # fleet-level scores on the latest trace (standing readout)
    lf = LF()
    tid = lf.latest_trace()
    if tid:
        for name, surf in out["surfaces"].items():
            ok = lf.post_score(tid, "factory:" + name, 1.0 if surf["verdict"] == "PASS" else 0.0,
                               "; ".join(surf["failures"]) or "all checks pass")
            print(f"  SCORE {name}: {tid} value={'1.0' if surf['verdict']=='PASS' else '0.0'} "
                  f"{'posted' if ok else 'FAILED'}")

    print("Evaluated S8+S9 → docs/evaluations/{}-hygiene.{{json,md}}".format(DATE))
    print("  S8 roster: PASS" if not roster_fails else "  S8 roster: FAIL → " + "; ".join(roster_fails))
    print("  S9 hygiene: PASS" if not hygiene_fails else "  S9 hygiene: FAIL → " + "; ".join(hygiene_fails))


if __name__ == "__main__":
    main()
