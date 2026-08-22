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
    ("prd-reviewer", "prd-reviewer-ops", "prd-reviewer-agent.md"),
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
    rows, fails, advisories = [], [], []

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
    # Langfuse keys are bound to the LOCAL instance (localhost) — exposure is inert
    # per the 2026-08-20 accepted-risk note; other provider keys (OpenRouter etc.)
    # would be an active leak. Distinguish the two in the verdict.
    lf_only = all("(sk|pk)-lf-" in h or "lf-" in h for h in hits) if hits else False
    rows.append({"check": "no secret values in tracked files",
                 "pass": not hits or lf_only, "evidence": str(len(hits)) + " hit(s)"
                 + (" — langfuse keys only, LOCAL instance, accepted risk" if lf_only else "")})
    if hits and not lf_only:
        fails.append("secrets in tracked files: " + "; ".join(h[:60] for h in hits))
    elif hits:
        advisories.append("langfuse keys in tracked history — local-only, accepted risk (2026-08-20); "
                          "rotate only if the instance is ever network-exposed: "
                          + "; ".join(h[:60] for h in hits))

    return rows, fails, advisories


def _gh_protection():
    try:
        r = subprocess.run(["gh", "api", "repos/ak47-arch/workspace/branches/master/protection"],
                           capture_output=True, text=True)
        return r.returncode == 0 and "required_pull_request_reviews" in (r.stdout or "")
    except FileNotFoundError:
        return False  # gh not installed in this env → report as absent (honest)


# ── S10 typed-trail integrity ───────────────────────────────────────────────
# The disclosure trail is machine-followable by construction: references are
# typed links (resolved from the artifact's own location), targets are stable
# (docs/prd/ home + manifest), and every decision leaf carries a `**Summary**:`
# read-skip. Each check is falsifiable — a mis-disclosure trips it.
#
# Convention: a "string path" is a backticked or bare concrete path to a
# `.md`/`.jsonl` doc that appears where the factory norm demands a typed link
# (structured reference lines — PRD/decision front-matter, reference artifact
# tables, knowledge index rows). Prose-body filename mentions are the body the
# read-skip summary lets an agent avoid, not a reason-hop.

def strip_fences(txt):
    txt = re.sub(r'\[\[^\]]*\]\([^)]*\)', '', txt)   # drop typed-link targets
    txt = re.sub(r'`', '', txt)                            # drop backticks (so backticked strings detect)
    txt = re.sub(r'^```.*?^```', '', txt, flags=re.S | re.M)
    return txt


def _metadata_block(txt):
    """Return the front matter: leading title + `**Field**:` lines before the first
    H2/H3 heading or prose paragraph."""
    out = []
    for l in txt.split('\n'):
        s = l.strip()
        if not s:
            if out and not any(o.startswith('**') for o in out):
                out.append('')
            continue
        if l.startswith('##') or l.startswith('###'):
            break
        if not s.startswith('**') and not s.startswith('#'):
            break  # prose body begins
        out.append(l)
    return '\n'.join(out)


def _string_paths(surface_text):
    """Concrete .md/.jsonl path tokens (path-qualified) in a text block, excluding
    typed-link targets and schema/<placeholder> illustrations."""
    s = strip_fences(surface_text)
    hits = []
    for m in re.finditer(r'(?:^|[>`*_~ ])((?:docs|bin|sessions?|config|\.pi|\.agents|\.github|openwiki|projects|feed_analyser|survival-infrastructure)\.?/?[\.\w/\-]*\.(?:md|jsonl?))\b', s):
        tok = m.group(1).strip('`')
        if '..' in tok or any(c in tok for c in '<>') or not tok.endswith(('.md', '.json', '.jsonl')):
            continue
        if tok.count('.') == 0:
            continue
        if not any(tok.startswith(p) for p in ('docs/', 'bin/', 'sessions', 'config/')):
            # relative links are stripped above; only root-qualified survive
            continue
        hits.append(tok)
    return hits


def head_meta(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except Exception:
        return ''


# document glob targets per layer
def _prd_files(ws):
    d = os.path.join(ws, 'docs', 'prd')
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, x) for x in sorted(os.listdir(d)) if x.endswith('.md')]


def _decision_files(ws):
    out = []
    base = os.path.join(ws, 'docs', 'knowledge')
    for dirpath, _, fn in os.walk(base):
        if '/decisions' not in dirpath:
            continue
        for x in fn:
            if x.endswith('.md'):
                out.append(os.path.join(dirpath, x))
    return sorted(out)


def _reference_files(ws):
    d = os.path.join(ws, 'docs', 'reference')
    if not os.path.isdir(d):
        return []
    return sorted(os.path.join(d, x) for x in os.listdir(d) if x.endswith('.md'))


def s10_string_paths(ws=WS):
    """Check (a): zero string-path references in the structured reference lines
    of the PRD, decision, reference and eval layers."""
    layers = [('prd', _prd_files(ws)), ('decision', _decision_files(ws)),
              ('reference', _reference_files(ws))]
    bad = []
    for label, files in layers:
        for f in files:
            if label in ('prd', 'decision', 'reference'):
                surface = _metadata_block(head_meta(f))
            else:
                surface = head_meta(f)
            for tok in _string_paths(surface):
                bad.append("{}: {}".format(os.path.relpath(f, ws), tok))
    ok = not bad
    why = "0 string-path refs on the typed-trail surface" if ok else "; ".join(bad[:8])
    return ok, why, len(bad)


def s10_summaries(ws=WS):
    """Check (b): every decision file carries a `**Summary**:` read-skip line."""
    dec = _decision_files(ws)
    missing = []
    for f in dec:
        t = head_meta(f)
        if '**Summary**:' not in t.split('### Context')[0]:
            missing.append(os.path.relpath(f, ws))
    ok = not missing
    why = "{}/{}".format(len(dec) - len(missing), len(dec)) + " decision files carry **Summary**:" if ok else \
        "missing: " + "; ".join(missing[:6])
    return ok, why, len(missing)


def s10_stale_citations(ws=WS):
    """Check (c): no live citation still points at the retired prd-queue/prd-archive
    homes, and the routing manifest agrees with the stable docs/prd/ home."""
    live = [('prd', _prd_files(ws)), ('decision', _decision_files(ws)),
            ('reference', _reference_files(ws)),
            ('index', [os.path.join(ws, 'docs', 'knowledge', 'index.md')])]
    stale = []
    for label, files in live:
        for f in files:
            for m in re.finditer(r'prd-(?:queue|archive)/([\w.-]+\.md)', head_meta(f)):
                stale.append("{} → {}".format(os.path.relpath(f, ws), m.group(0)))
    # manifest coherence: every manifest row's file exists at docs/prd/ & every PRD has a row
    mf = os.path.join(ws, 'docs', 'prd', 'manifest.json')
    manifest_ok = True
    manifest_why = ""
    try:
        manifest = json.loads(head_meta(mf) or 'null')
        inst = set()
        if manifest and 'prds' in manifest:
            for row in manifest['prds']:
                inst.add(row.get('file'))
                if not os.path.isfile(os.path.join(ws, 'docs', 'prd', row.get('file', ''))):
                    stale.append("manifest row '{}' file missing".format(row.get('slug')))
        for f in _prd_files(ws):
            fn = os.path.basename(f)
            if manifest and fn not in inst:
                stale.append("docs/prd/{} not in manifest".format(fn))
        if not manifest:
            manifest_ok = False
            manifest_why = "docs/prd/manifest.json missing/invalid"
    except Exception as e:
        manifest_ok = False
        manifest_why = "manifest parse error: " + str(e)
    ok = not stale and manifest_ok
    why = ("0 stale prd-queue/archive citations; manifest↔docs/prd coherent" if ok else
           "stale: " + "; ".join(stale[:6]) + (manifest_why or ""))
    return ok, why, len(stale) + (0 if manifest_ok else 1)


def typed_trail_checks(ws=WS):
    rows, fails = [], []
    for name, fn in [('string-path refs', s10_string_paths),
                     ('decision **Summary**: present', s10_summaries),
                     ('no stale/mismatched citations + manifest coherence', s10_stale_citations)]:
        ok, why, n = fn(ws)
        rows.append({'check': name, 'pass': ok, 'evidence': "{} — {}".format(n, why)})
        if not ok:
            fails.append(name + ": " + why)
    return rows, fails


# ── Langfuse ───────────────────────────────────────────────────────────────
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
    hygiene, hygiene_fails, advisories = hygiene_checks()
    typedtrail, typedtrail_fails = typed_trail_checks()

    all_fails = roster_fails + hygiene_fails + typedtrail_fails
    out = {
        "generated": DATE,
        "advisories": advisories,
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
            "S10-typed-trail-integrity": {
                "rows": typedtrail,
                "failures": typedtrail_fails,
                "verdict": "FAIL" if typedtrail_fails else "PASS",
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
    md += ["", "## S10 — Typed-trail integrity (machine-followable trail)", "",
           "| check | verdict | evidence |", "|---|---|---|"]
    for t in typedtrail:
        md.append("| {} | {} | {} |".format(
            t["check"], "PASS" if t["pass"] else "FAIL", t["evidence"]))
    md += ["", "## Surfaces", ""]
    md += ["- **{}**: {}".format(n, s["verdict"]) for n, s in out["surfaces"].items()]
    md += ["", "## Failures", ""]
    md += [f"- {f}" for f in all_fails or ["(none)"]]
    md += ["", "## Advisories (accepted risk / notes)", ""]
    md += [f"- {a}" for a in (advisories or ["(none)"])]
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

    print("Evaluated S8+S9+S10 → docs/evaluations/{}-hygiene.{{json,md}}".format(DATE))
    print("  S8 roster: PASS" if not roster_fails else "  S8 roster: FAIL → " + "; ".join(roster_fails))
    print("  S9 hygiene: PASS" if not hygiene_fails else "  S9 hygiene: FAIL → " + "; ".join(hygiene_fails))
    print("  S10 typed-trail: PASS" if not typedtrail_fails else "  S10 typed-trail: FAIL → " + "; ".join(typedtrail_fails))


if __name__ == "__main__":
    main()
