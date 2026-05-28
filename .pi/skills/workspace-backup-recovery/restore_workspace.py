#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEFAULT_MANIFEST = ROOT / "workspace_restore_manifest.json"


def run(cmd, cwd=None, capture_output=False):
    print("+", " ".join(cmd))
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=True,
        text=True,
        capture_output=capture_output,
    )


def require_command(cmd):
    if shutil.which(cmd) is None:
        raise SystemExit(f"Required command not found: {cmd}")


def load_manifest(path: Path):
    with path.open() as f:
        return json.load(f)


def latest_remote_artifact(remote: str, prefix: str) -> str:
    result = run([
        "rclone",
        "lsf",
        "--files-only",
        remote,
        "--include",
        f"{prefix}*.tar.gz",
    ], capture_output=True)
    candidates = sorted(line.strip() for line in result.stdout.splitlines() if line.strip())
    if not candidates:
        raise SystemExit(f"No snapshot artifacts found in remote: {remote}")
    return candidates[-1]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_checksum(artifact: Path, checksum_file: Path):
    expected_line = checksum_file.read_text().strip()
    if not expected_line:
        raise SystemExit(f"Checksum file is empty: {checksum_file}")
    expected_hash = expected_line.split()[0]
    actual_hash = sha256_file(artifact)
    if expected_hash != actual_hash:
        raise SystemExit(
            f"Checksum mismatch for {artifact.name}: expected {expected_hash}, got {actual_hash}"
        )


def download_snapshot(remote: str, artifact_name: str, temp_dir: Path):
    artifact = temp_dir / artifact_name
    checksum = temp_dir / f"{artifact_name}.sha256"
    run(["rclone", "copyto", f"{remote}/{artifact_name}", str(artifact)])
    run(["rclone", "copyto", f"{remote}/{artifact_name}.sha256", str(checksum)])
    verify_checksum(artifact, checksum)
    return artifact, checksum


def extract_snapshot(artifact: Path, extract_to: Path):
    with tarfile.open(artifact, "r:gz") as tf:
        tf.extractall(extract_to)


def repo_path(dest: Path, repo_rel_path: str) -> Path:
    return dest if repo_rel_path == "." else dest / repo_rel_path


def ensure_repo(repo, dest: Path):
    target = repo_path(dest, repo["path"])
    primary_remote = repo["primary_remote"]
    branch = repo["branch"]
    clone_url = repo["clone_url"]

    if repo["path"] == ".":
        target_parent = target.parent
    else:
        target_parent = target.parent
        target_parent.mkdir(parents=True, exist_ok=True)

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


def remove_path(path: Path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def restore_paths(extract_root: Path, dest: Path, restore_list):
    for rel in restore_list:
        src = extract_root / rel
        target = dest / rel
        if not src.exists():
            raise SystemExit(f"Expected restore path missing from snapshot: {src}")
        if target.exists():
            remove_path(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            shutil.copytree(src, target)
        else:
            shutil.copy2(src, target)
        print(f"Restored {rel}")


def parse_args():
    p = argparse.ArgumentParser(description="Restore full workspace from git remotes and Drive snapshot")
    p.add_argument("destination", help="Destination directory for restored workspace")
    p.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    p.add_argument("--snapshot-remote", help="Override snapshot remote, e.g. workspace:workspace-critical-snapshot")
    p.add_argument("--artifact", help="Specific artifact file name to restore")
    p.add_argument("--skip-download", action="store_true", help="Use existing local artifact from --local-artifact")
    p.add_argument("--local-artifact", help="Path to a local snapshot tar.gz")
    return p.parse_args()


def main():
    require_command("git")
    require_command("tar")

    args = parse_args()
    if not args.skip_download:
        require_command("rclone")
    manifest = load_manifest(Path(args.manifest))
    dest = Path(args.destination).expanduser().resolve()
    snapshot_cfg = manifest["snapshot"]
    remote = args.snapshot_remote or snapshot_cfg["remote"]
    extract_root_name = snapshot_cfg["extract_root"]

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
                remote, snapshot_cfg["artifact_prefix"]
            )
            print(f"Using remote snapshot: {artifact_name}")
            artifact, _checksum = download_snapshot(remote, artifact_name, tmpdir)

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
