#!/usr/bin/env python3
"""Falsifiability proof for the S10 typed-trail-integrity checks (see
bin/test-typed-trail-integrity.sh). Builds a minimal fixture workspace and
proves each check can be flipped to FAIL by a mis-disclosure injection:
  (a) string-path refs — a backticked string path in the PRD front-matter
  (b) Summary present  — removing the decision's read-skip summary line
  (c) stale/mismatch   — a stale prd-queue/<file>.md citation + manifest break
Clean fixture must PASS all three (no can't-fail rows). Exits 1 on any failure.
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def build_fixture(ws):
    prd = os.path.join(ws, "docs", "prd")
    dec = os.path.join(ws, "docs", "knowledge", "sessions",
                       "00000000-0000-4000-8000-000000000000", "decisions")
    reff = os.path.join(ws, "docs", "reference")
    os.makedirs(prd, exist_ok=True)
    os.makedirs(os.path.join(ws, "docs", "tasks"), exist_ok=True)
    os.makedirs(dec, exist_ok=True)
    os.makedirs(reff, exist_ok=True)
    # PRD with fully-typed front-matter (story 1 convention)
    with open(os.path.join(prd, "2026-08-01-foo.md"), "w") as f:
        f.write("# PRD: Foo\n\n"
                "**Date**: 2026-08-01\n"
                "**Status**: [Final](./manifest.json)\n"
                "**Task**: [foo](../tasks/foo.md)\n"
                "**Session**: [session.jsonl](../knowledge/sessions/00000000-0000-4000-8000-000000000000/session.jsonl)\n"
                "**Decisions**:\n"
                "  - [01-bar](../knowledge/sessions/00000000-0000-4000-8000-000000000000/decisions/01-bar.md)\n")
    with open(os.path.join(ws, "docs", "tasks", "foo.md"), "w") as f:
        f.write("# Task: foo\n\n**Status**: prd-ready\n")
    with open(os.path.join(prd, "manifest.json"), "w") as f:
        f.write('{"version": 1, "prds": [{"slug": "foo", "file": "2026-08-01-foo.md", '
                '"status": "final", "ordering_key": "2026-08-01-foo"}]}\n')
    # decision with typed Session + Summary
    with open(os.path.join(dec, "01-bar.md"), "w") as f:
        f.write("## Decision: Bar\n\n"
                "**Status**: accepted\n**Date**: 2026-08-01\n"
                "**Task**: [foo](../../../../tasks/foo.md)\n"
                "**Session**: [session.jsonl](../session.jsonl)\n"
                "**Summary**: Bar is decided.\n\n"
                "### Context\n\nThe decision.\n")
    with open(os.path.join(reff, "agent.md"), "w") as f:
        f.write("| Artifact | Location |\n|---|---|\n"
                "| PRD | `docs/prd/<date>-<slug>.md` |\n")


def run_checks(ws, tests):
    """Yield (ok, why, n) for the three S10 checks against ws."""
    m = load("eh", os.path.join(WS, "bin", "eval-hygiene.py"))
    for name, fn in tests:
        yield name, fn(ws)


TESTS = [("string-path", lambda ws: ("x",) ),
         ("summary", lambda ws: ("x",)),
         ("stale", lambda ws: ("x",))]


def main():
    import importlib.util as il
    spec = il.spec_from_file_location("eh", os.path.join(WS, "bin", "eval-hygiene.py"))
    eh = il.module_from_spec(spec)
    spec.loader.exec_module(eh)

    tmp = tempfile.mkdtemp(prefix="ttl-")
    fails = []
    try:
        # ── clean fixture must PASS all three ──
        build_fixture(tmp)
        clean = {
            "string-path": eh.s10_string_paths(tmp),
            "summary": eh.s10_summaries(tmp),
            "stale": eh.s10_stale_citations(tmp),
        }
        for name, (ok, why, n) in clean.items():
            tag = "PASS" if ok else "FAIL"
            print(f"clean {name}: {tag} — {why}")
            if not ok:
                fails.append(f"clean fixture should PASS {name}: {why}")

        # ── injection (a): backticked string path in PRD front-matter ──
        p = os.path.join(tmp, "docs", "prd", "2026-08-01-foo.md")
        t = open(p).read()
        open(p, "w").write(t.replace("**Status**: [Final](./manifest.json)",
                                     "**Status**: `docs/prd/2026-08-01-foo.md`"))
        ok, why, n = eh.s10_string_paths(tmp)
        print(f"inject string-path: {'FAIL (flipped)' if not ok else 'STILL PASS'} — {why}")
        if ok:
            fails.append("string-path check did NOT trip on injected backticked path")
        open(p, "w").write(t)  # restore

        # ── injection (b): remove the summary line ──
        d = os.path.join(tmp, "docs", "knowledge", "sessions",
                         "00000000-0000-4000-8000-000000000000", "decisions", "01-bar.md")
        t = open(d).read()
        open(d, "w").write(t.replace("**Summary**: Bar is decided.\n", ""))
        ok, why, n = eh.s10_summaries(tmp)
        print(f"inject remove-summary: {'FAIL (flipped)' if not ok else 'STILL PASS'} — {why}")
        if ok:
            fails.append("summary check did NOT trip on removed **Summary**:")
        open(d, "w").write(t)

        # ── injection (c): stale prd-queue/ citation + broken manifest ──
        d = os.path.join(tmp, "docs", "knowledge", "sessions",
                         "00000000-0000-4000-8000-000000000000", "decisions", "01-bar.md")
        t = open(d).read()
        open(d, "w").write(t + "\nPRD `docs/prd-queue/2026-08-01-foo.md`.\n")
        ok, why, n = eh.s10_stale_citations(tmp)
        print(f"inject stale-citation: {'FAIL (flipped)' if not ok else 'STILL PASS'} — {why}")
        if ok:
            fails.append("stale check did NOT trip on injected prd-queue/ citation")
        open(d, "w").write(t)
        # manifest/PRD mismatch (a PRD file with no manifest row)
        with open(os.path.join(tmp, "docs", "prd", "2026-08-02-orphan.md"), "w") as f:
            f.write("# PRD: Orphan\n\n**Date**: 2026-08-02\n**Status**: Final\n")
        ok, why, n = eh.s10_stale_citations(tmp)
        print(f"inject manifest-mismatch: {'FAIL (flipped)' if not ok else 'STILL PASS'} — {why}")
        if ok:
            fails.append("stale check did NOT trip on unmatched docs/prd/ file")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if fails:
        print("typed-trail falsifiability: FAILED")
        for f2 in fails:
            print("  ✗ " + f2)
        return 1
    print("typed-trail falsifiability: PASS (all 3 checks flippable; clean fixture green)")
    return 0


if __name__ == "__main__":
    sys.exit(main())