#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from portability_lib import (
    DEFAULT_MANIFEST,
    decrypt_if_needed,
    download_artifact,
    extract_snapshot,
    latest_remote_artifact,
    load_manifest,
    repo_path,
    require_command,
    restore_paths,
    run,
    verify_checksum,
)


def ensure_repo(repo, dest: Path):
    target = repo_path(dest, repo["path"])
    primary_remote = repo["primary_remote"]
    branch = repo["branch"]
    clone_url = repo["clone_url"]

    target.parent.mkdir(parents=True, exist_ok=True)

    if not target.exists():
        run(["git", "clone", clone_url, str(target)])
    elif not (target / ".git").exists():
        raise SystemExit(f"Destination exists but is not a git repo: {target}")

    existing_remotes = {
        line.split()[0]
        for line in run(["git", "remote"], cwd=target, capture_output=True).stdout.splitlines()
        if line.strip()
    }

    if primary_remote == "origin":
        if "origin" not in existing_remotes:
            run(["git", "remote", "add", "origin", clone_url], cwd=target)
        else:
            run(["git", "remote", "set-url", "origin", clone_url], cwd=target)
    else:
        if primary_remote not in existing_remotes and "origin" in existing_remotes:
            run(["git", "remote", "rename", "origin", primary_remote], cwd=target)
        elif primary_remote not in existing_remotes:
            run(["git", "remote", "add", primary_remote, clone_url], cwd=target)
        run(["git", "remote", "set-url", primary_remote, clone_url], cwd=target)
        existing_remotes = {
            line.split()[0]
            for line in run(["git", "remote"], cwd=target, capture_output=True).stdout.splitlines()
            if line.strip()
        }

    for remote_name, remote_url in repo.get("extra_remotes", {}).items():
        if remote_name in existing_remotes:
            run(["git", "remote", "set-url", remote_name, remote_url], cwd=target)
        else:
            run(["git", "remote", "add", remote_name, remote_url], cwd=target)

    run(["git", "fetch", "--all", "--prune"], cwd=target)

    remote_branch = f"{primary_remote}/{branch}"
    remote_check = subprocess.run(
        ["git", "show-ref", "--verify", f"refs/remotes/{remote_branch}"],
        cwd=str(target),
        text=True,
        capture_output=True,
    )
    if remote_check.returncode != 0:
        raise SystemExit(f"Remote branch not found: {remote_branch} for repo {target}")

    local_branch_check = subprocess.run(
        ["git", "show-ref", "--verify", f"refs/heads/{branch}"],
        cwd=str(target),
        text=True,
        capture_output=True,
    )
    if local_branch_check.returncode == 0:
        run(["git", "checkout", branch], cwd=target)
    else:
        run(["git", "checkout", "-B", branch, "--track", remote_branch], cwd=target)

    run(["git", "reset", "--hard", remote_branch], cwd=target)


def parse_args():
    p = argparse.ArgumentParser(description="Restore full workspace from git remotes and critical snapshot")
    p.add_argument("destination", help="Destination directory for restored workspace")
    p.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    p.add_argument("--snapshot-remote", help="Override snapshot remote")
    p.add_argument("--artifact", help="Specific artifact file name to restore")
    p.add_argument("--skip-download", action="store_true", help="Use existing local artifact from --local-artifact")
    p.add_argument("--local-artifact", help="Path to a local snapshot tar.gz or tar.gz.age")
    p.add_argument("--age-identity-file", help="Identity file used to decrypt .age artifacts")
    return p.parse_args()


def main():
    require_command("git")
    require_command("tar")

    args = parse_args()
    manifest = load_manifest(Path(args.manifest))
    dest = Path(args.destination).expanduser().resolve()
    snapshot_cfg = manifest["snapshot"]
    remote = args.snapshot_remote or snapshot_cfg["remote"]
    extract_root_name = snapshot_cfg["extract_root"]

    if not args.skip_download:
        require_command("rclone")

    if dest.exists() and any(dest.iterdir()) and not (dest / ".git").exists():
        raise SystemExit(
            f"Destination exists and is not an initialized workspace git repo: {dest}"
        )
    dest.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="workspace-restore-") as tmp:
        tmpdir = Path(tmp)

        if args.skip_download:
            if not args.local_artifact:
                raise SystemExit("--skip-download requires --local-artifact")
            artifact = Path(args.local_artifact).expanduser().resolve()
            if not artifact.exists():
                raise SystemExit(f"Local artifact not found: {artifact}")
            local_checksum = artifact.with_name(f"{artifact.name}.sha256")
            if local_checksum.exists():
                verify_checksum(artifact, local_checksum)
        else:
            artifact_name = args.artifact or latest_remote_artifact(
                remote,
                snapshot_cfg["artifact_prefix"],
                snapshot_cfg.get("extensions", [".tar.gz"]),
            )
            print(f"Using remote snapshot: {artifact_name}")
            artifact = download_artifact(remote, artifact_name, tmpdir)

        artifact = decrypt_if_needed(artifact, args.age_identity_file)

        extract_dir = tmpdir / "extract"
        extract_dir.mkdir(parents=True, exist_ok=True)
        extract_snapshot(artifact, extract_dir)

        snapshot_root = extract_dir / extract_root_name
        if not snapshot_root.exists():
            raise SystemExit(f"Snapshot root missing after extraction: {snapshot_root}")

        for repo in manifest["repos"]:
            ensure_repo(repo, dest)

        restore_paths(snapshot_root, dest, manifest["restore_paths"])

    print(f"Workspace restored at: {dest}")


if __name__ == "__main__":
    main()
