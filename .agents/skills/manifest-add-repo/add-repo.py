#!/usr/bin/env python3
"""
add-repo.py — Register a newly cloned repo in the workspace-portability manifest.

Usage:
  python3 .agents/skills/manifest-add-repo/add-repo.py opensource/new-repo
  python3 .agents/skills/manifest-add-repo/add-repo.py opensource/new-repo --manifest /path/to/manifest.json

The script auto-detects the workspace root from its own location.
It adds the repo to the 'additional_repos' section of the manifest.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run_git(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git"] + cmd,
        cwd=str(cwd),
        capture_output=True,
        text=True,
    )


def get_workspace_root() -> Path:
    """Resolve workspace root from the script's location.

    Script lives at:  .agents/skills/manifest-add-repo/add-repo.py
    Workspace root is 4 levels up.
    """
    return Path(__file__).resolve().parent.parent.parent.parent


def get_repo_metadata(repo_abs: Path) -> dict:
    """Extract git metadata from a valid git repo."""
    # Current branch
    result = run_git(["rev-parse", "--abbrev-ref", "HEAD"], repo_abs)
    if result.returncode != 0:
        print(f"✗ Failed to get current branch: {result.stderr.strip()}")
        sys.exit(1)
    branch = result.stdout.strip()

    # List remotes
    result = run_git(["remote"], repo_abs)
    if result.returncode != 0:
        print(f"✗ Failed to list remotes: {result.stderr.strip()}")
        sys.exit(1)
    remotes = [r for r in result.stdout.strip().splitlines() if r]

    if not remotes:
        print(f"✗ No git remotes configured for {repo_abs}")
        sys.exit(1)

    # Primary remote: prefer "origin", otherwise the first one
    primary_remote = "origin" if "origin" in remotes else remotes[0]

    # Primary remote URL
    result = run_git(["remote", "get-url", primary_remote], repo_abs)
    if result.returncode != 0:
        print(f"✗ Failed to get URL for remote '{primary_remote}': {result.stderr.strip()}")
        sys.exit(1)
    clone_url = result.stdout.strip()

    # Extra remotes (everything besides primary)
    extra_remotes: dict[str, str] = {}
    for r in remotes:
        if r != primary_remote:
            result = run_git(["remote", "get-url", r], repo_abs)
            if result.returncode == 0:
                extra_remotes[r] = result.stdout.strip()

    return {
        "primary_remote": primary_remote,
        "clone_url": clone_url,
        "branch": branch,
        "extra_remotes": extra_remotes,
    }


def find_manifest(workspace_root: Path, explicit_path: str | None = None) -> Path:
    """Locate the workspace_restore_manifest.json."""
    if explicit_path:
        p = Path(explicit_path)
        if p.exists():
            return p
        print(f"✗ Specified manifest not found: {p}")
        sys.exit(1)

    candidates = [
        workspace_root / "workspace-portability" / "workspace_restore_manifest.json",
        workspace_root / "workspace_restore_manifest.json",
    ]
    for c in candidates:
        if c.exists():
            return c

    print("✗ workspace_restore_manifest.json not found")
    print(f"  Looked in: {[str(c) for c in candidates]}")
    print("  Specify with --manifest")
    sys.exit(1)


def main() -> None:
    p = argparse.ArgumentParser(
        description="Register a newly cloned repo in the workspace-portability manifest"
    )
    p.add_argument(
        "repo_path",
        help="Path to the repo, relative to workspace root (e.g. opensource/new-repo)",
    )
    p.add_argument(
        "--manifest",
        help="Path to workspace_restore_manifest.json (auto-detected by default)",
    )
    args = p.parse_args()

    workspace_root = get_workspace_root()
    repo_abs = workspace_root / args.repo_path
    manifest_path = find_manifest(workspace_root, args.manifest)

    # ── Validate repo ──────────────────────────────────────────────
    if not repo_abs.exists():
        print(f"✗ Path does not exist: {repo_abs}")
        sys.exit(1)

    if not (repo_abs / ".git").exists():
        print(f"✗ Not a git repository (no .git directory): {repo_abs}")
        sys.exit(1)

    # ── Extract metadata ────────────────────────────────────────────
    metadata = get_repo_metadata(repo_abs)

    # ── Load manifest ───────────────────────────────────────────────
    with open(manifest_path) as f:
        manifest = json.load(f)

    # ── Check for duplicates ────────────────────────────────────────
    all_repos = manifest.get("repos", []) + manifest.get("additional_repos", [])
    existing_paths = {r["path"] for r in all_repos}

    if args.repo_path in existing_paths:
        print(f"✓ Repo '{args.repo_path}' is already in the manifest. No changes needed.")
        for r in all_repos:
            if r["path"] == args.repo_path:
                print(f"  Existing entry: {json.dumps(r, indent=2)}")
                break
        sys.exit(0)

    # ── Build new entry ────────────────────────────────────────────
    new_entry: dict = {
        "path": args.repo_path,
        "primary_remote": metadata["primary_remote"],
        "clone_url": metadata["clone_url"],
        "branch": metadata["branch"],
        "extra_remotes": metadata["extra_remotes"],
    }

    # ── Update manifest ────────────────────────────────────────────
    manifest.setdefault("additional_repos", []).append(new_entry)
    manifest["additional_repos"].sort(key=lambda r: r["path"])

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    # ── Report ──────────────────────────────────────────────────────
    print(f"✓ Added '{args.repo_path}' to {manifest_path}")
    print(f"  Entry:")
    print(f"    path:             {args.repo_path}")
    print(f"    primary_remote:   {metadata['primary_remote']}")
    print(f"    clone_url:        {metadata['clone_url']}")
    print(f"    branch:           {metadata['branch']}")
    if metadata["extra_remotes"]:
        print(f"    extra_remotes:    {json.dumps(metadata['extra_remotes'])}")
    print()
    print(f"  Run sync-repos.sh to include it in future syncs.")


if __name__ == "__main__":
    main()