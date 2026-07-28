#!/usr/bin/env python3
"""
add-repo.py — Register repos from opensource/ in the workspace-portability manifest.

Deterministically scans the opensource/ directory for git repos, compares them
against the manifest (workspace-portability/workspace_restore_manifest.json), and
adds any repos that exist on disk but are missing from the manifest.

Usage:
  python3 .agents/skills/manifest-add-repo/add-repo.py
  python3 .agents/skills/manifest-add-repo/add-repo.py --manifest /path/to/manifest.json

The script auto-detects the workspace root from its own location.
It adds missing repos to the 'additional_repos' section of the manifest.
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


def get_repo_metadata(repo_abs: Path) -> dict | None:
    """Extract git metadata from a valid git repo. Returns None if not a git repo."""
    if not (repo_abs / ".git").exists():
        return None

    # Current branch
    result = run_git(["rev-parse", "--abbrev-ref", "HEAD"], repo_abs)
    if result.returncode != 0:
        return None
    branch = result.stdout.strip()

    # List remotes
    result = run_git(["remote"], repo_abs)
    if result.returncode != 0:
        return None
    remotes = [r for r in result.stdout.strip().splitlines() if r]

    if not remotes:
        return None

    # Primary remote: prefer "origin", otherwise the first one
    primary_remote = "origin" if "origin" in remotes else remotes[0]

    # Primary remote URL
    result = run_git(["remote", "get-url", primary_remote], repo_abs)
    if result.returncode != 0:
        return None
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


def get_existing_paths(manifest: dict) -> set[str]:
    """Return the set of all repo paths already registered in the manifest."""
    paths = set()
    for key in ("repos", "additional_repos"):
        for entry in manifest.get(key, []):
            if "path" in entry:
                paths.add(entry["path"])
    return paths


def discover_opensource_repos(workspace_root: Path) -> list[Path]:
    """Return a sorted list of opensource/ subdirectories that are git repos."""
    opensource_dir = workspace_root / "opensource"
    if not opensource_dir.is_dir():
        return []

    repos = sorted([
        d for d in opensource_dir.iterdir()
        if d.is_dir() and (d / ".git").exists()
    ])
    return repos


def main() -> None:
    p = argparse.ArgumentParser(
        description="Register opensource/ repos missing from the workspace-portability manifest"
    )
    p.add_argument(
        "--manifest",
        help="Path to workspace_restore_manifest.json (auto-detected by default)",
    )
    args = p.parse_args()

    workspace_root = get_workspace_root()
    manifest_path = find_manifest(workspace_root, args.manifest)

    # ── Load manifest ───────────────────────────────────────────────
    with open(manifest_path) as f:
        manifest = json.load(f)

    existing_paths = get_existing_paths(manifest)

    # ── Discover repos in opensource/ ───────────────────────────────
    opensource_repos = discover_opensource_repos(workspace_root)
    if not opensource_repos:
        print("No git repos found in opensource/")
        sys.exit(0)

    # ── Find missing repos ──────────────────────────────────────────
    missing: list[tuple[Path, dict]] = []
    for repo_abs in opensource_repos:
        rel_path = f"opensource/{repo_abs.name}"

        if rel_path in existing_paths:
            continue

        metadata = get_repo_metadata(repo_abs)
        if metadata is None:
            print(f"⚠ Skipping '{rel_path}' — unable to read git metadata")
            continue

        missing.append((repo_abs, metadata))

    if not missing:
        print("✓ All opensource/ repos are already registered in the manifest.")
        sys.exit(0)

    # ── Add missing repos to manifest ───────────────────────────────
    manifest.setdefault("additional_repos", [])

    for repo_abs, metadata in missing:
        rel_path = f"opensource/{repo_abs.name}"
        new_entry = {
            "path": rel_path,
            "primary_remote": metadata["primary_remote"],
            "clone_url": metadata["clone_url"],
            "branch": metadata["branch"],
            "extra_remotes": metadata["extra_remotes"],
        }
        manifest["additional_repos"].append(new_entry)
        existing_paths.add(rel_path)  # prevent duplicates within same run

    manifest["additional_repos"].sort(key=lambda r: r["path"])

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    # ── Report ──────────────────────────────────────────────────────
    print(f"✓ Added {len(missing)} missing repo(s) to {manifest_path}")
    for repo_abs, metadata in missing:
        rel_path = f"opensource/{repo_abs.name}"
        print(f"  - {rel_path}")
        print(f"    primary_remote:   {metadata['primary_remote']}")
        print(f"    clone_url:        {metadata['clone_url']}")
        print(f"    branch:           {metadata['branch']}")
        if metadata["extra_remotes"]:
            print(f"    extra_remotes:    {json.dumps(metadata['extra_remotes'])}")


if __name__ == "__main__":
    main()