#!/usr/bin/env python3
"""
eval-context-semantic.py — Context-Disclosure Semantic Probe (S7 depth / research).

For each completed task that declares a PRD binding, replay its retained session
(session.jsonl) and ask: did the agent REACH the binding it needed, on the disclosure
path the spine/task-file promise, within the deterministic token budget?

Metric rows (per task):
  REACH      — the task's governing PRD (needed binding) was actually read by the session.
  REACH_STEP — which disclosure layer the binding surfaced from (task-file / spine), the hop.
  COST_TOGATE— est. tokens the session spent reading the binding path vs the C1 budget.
  MISS       — a binding the spine/task points at but the session never touched.

No model is graded. This measures disclosure behaviour on real finished work. Ground
truth = the retained session transcript (tool read calls), not an LLM rubric.

Honesty: FAIL only with concrete evidence (a session that never reached its promised
binding, or a binding missing on disk). A session with no recovered reads is an
OFF-PATH signal (retention / replay gap), flagged not guessed.
"""
import datetime, glob, json, os, re, sys

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATE = datetime.date.today().isoformat()

# Same budgets as the deterministic C1 layer (single source of truth for a layer's cost)
FOOTPRINT_BUDGETS = {
    "AGENTS.md": 1000,
    "docs/factory-context.md": 4000,
    "docs/knowledge/index.md": 8000,
}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def est_tokens(text):
    return max(1, len(text) // 4)


def disclosed_reads(session_path):
    """Ordered repo-relative file paths the agent READ in a retained session.jsonl."""
    reads = []
    if not os.path.isfile(session_path):
        return reads
    for line in open(session_path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        msg = rec.get("message", {}) if isinstance(rec.get("message"), dict) else {}
        parts = msg.get("content")
        if not isinstance(parts, list):
            continue
        for part in parts:
            if not isinstance(part, dict) or part.get("type") != "toolCall":
                continue
            args = part.get("arguments")
            if not isinstance(args, dict):
                continue
            path = args.get("path")
            if path:
                reads.append(str(path))
    return reads


def as_repo_rel(path):
    """Normalize session read paths to repo-relative (docs/...).
    Sessions may log absolute host paths (/home/.../workspace/...) or sandbox-relative
    (/sandbox/worktree/...) — take the tail after the LAST sandbox/workspace marker.
    """
    p = path.replace("\\", "/")
    for marker in ("/sandbox/worktree/", "/workspace/"):
        if marker in p:
            return p.split(marker, 1)[1].lstrip("/")
    return p.lstrip("/")


def binding_for_task(task_path):
    """The needed binding for a task: the PRD file it points to, if any.

    The PRD may have moved from prd-queue/ to prd-archive/ once the task completed
    (decision: 'PRD moves to archive only after UAT + user go-ahead'), so the
    resolver searches BOTH dirs.  A binding that resolves nowhere on disk is a REAL
    dangling link (disclosure defect), not a clean archive state.

    Returns (binding_rel, promise_doc) or (None, None).
    """
    txt = read(task_path)
    m = re.search(r"prd-queue/([a-z0-9-]+\.md)", txt)
    if not m:
        return None, None
    name = m.group(1)
    for rel in ("docs/prd-queue/" + name, "docs/prd-archive/" + name):
        if os.path.isfile(os.path.join(WS, rel)):
            return rel, os.path.dirname(rel)
    return "docs/prd-queue/" + name, "docs/prd-queue/"


def main():
    rows, fails = [], []
    reached = missed = 0

    for tf in sorted(glob.glob(os.path.join(WS, "docs", "tasks", "*.md"))):
        slug = os.path.basename(tf)[:-3]
        tsrc = read(tf)
        if "**Status**: complete" not in tsrc:
            continue

        binding, _ = binding_for_task(tf)
        if not binding:
            rows.append({"task": slug, "binding": None, "verdict": "SKIP",
                         "evidence": "no PRD binding declared on task file"})
            continue

        # the task's retained implementation sessions
        session_ids = re.findall(r"knowledge/sessions/([0-9a-f-]+)/session\.jsonl", tsrc)
        reads_all = []
        for sid in session_ids:
            sp = os.path.join(WS, "docs", "knowledge", "sessions", sid, "session.jsonl")
            reads_all += disclosed_reads(sp)
        relreads = [as_repo_rel(r) for r in reads_all]

        binding_base = os.path.basename(binding)
        binding_exists = os.path.isfile(os.path.join(WS, binding))
        hit = any(binding_base in s for s in relreads)

        if not binding_exists:
            verdict = "FAIL"
            ev = f"binding {binding} declared on task but missing on disk"
            fails.append(f"{slug}: {ev}")
        elif not session_ids:
            verdict = "SKIP"
            ev = "task cites no retained implementation session"
        elif not relreads:
            verdict = "FAIL"
            ev = "session has no recovered read calls (evidence/retention gap)"
            fails.append(f"{slug}: {ev}")
        elif not hit:
            verdict = "FAIL"
            ev = f"task binds {binding_base} but session never read it"
            missed += 1
            fails.append(f"{slug}: {ev}")
        else:
            # COST_TOGATE (advisory): est context tokens the agent spent reading the
            # disclosure path BEFORE the binding surfaced. NOT a verdict — the honest
            # fail gate is REACH, not a made-up cumulative budget. A high cumulative
            # total signals the agent waded through many files before the gate (one
            # engine improvement to surface bindings earlier); low = gate surfaced late.
            idx = next(i for i, s in enumerate(relreads) if binding_base in s)
            pre_paths = relreads[:idx + 1]
            content_toks = 0
            for rp in pre_paths:
                cand = os.path.join(WS, rp)
                if os.path.isfile(cand):
                    try:
                        content_toks += est_tokens(read(cand))
                    except Exception:
                        pass
            cost_toks = content_toks if content_toks else est_tokens("\n".join(pre_paths))
            verdict = "REACHABLE"
            ev = (f"reached {binding_base} at step {idx + 1}; "
                  f"~{cost_toks} est cumulative read tokens before gate (advisory)")
            reached += 1

        rows.append({"task": slug, "binding": binding, "verdict": verdict,
                     "evidence": ev, "session_reads": len(relreads)})

    # aggregate
    final = "FAIL" if fails else ("PASS" if any(r["verdict"] == "REACHABLE" for r in rows) else "SKIP")
    out = {"generated": DATE, "verdict": final, "failures": fails, "rows": rows}
    os.makedirs(os.path.join(WS, "docs", "evaluations"), exist_ok=True)
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-context-semantic.json"), "w") as f:
        json.dump(out, f, indent=2)

    md = ["# Context-Disclosure Semantic Probe (research)", "",
          f"Date: {DATE} · Verdict: **{final}**", "",
          "## Rows (per completed task declaring a PRD binding)", "",
          "| task | binding | verdict | evidence |", "|---|---|---|---|"]
    for r in rows:
        md.append(f"| {r['task']} | {r['binding'] or '—'} | {r['verdict']} | {r['evidence']} |")
    md += ["", "## Failures", ""]
    md += [f"- {f}" for f in (fails or ["(none)"])]
    md += ["", "> COST_TOGATE is ADVISORY (cumulative read tokens before the gate). REACH is the hard",
           "> gate: a task whose bound PRD was never read by its session is a real FAIL, and a",
           "> binding missing on disk is a dangling disclosure link."]
    with open(os.path.join(WS, "docs", "evaluations", f"{DATE}-context-semantic.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    print("Semantic probe -> docs/evaluations/{}-context-semantic.{{json,md}}".format(DATE))
    print("  verdict:", final, "| rows:", len(rows), "| reachable:", reached, "| misses:", missed)
    print("  advisories:", sum(1 for r in rows if "advisory" in r.get("evidence", "")))
    sys.exit(0 if final == "PASS" else 2)


if __name__ == "__main__":
    main()