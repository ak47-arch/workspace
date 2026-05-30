#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from portability_lib import DEFAULT_MANIFEST, load_manifest, parse_env_file, repo_path, wait_for_http


def current_branch(repo_dir: Path) -> str:
    result = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=str(repo_dir),
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def verify_repos(dest: Path, manifest, errors: list[str]):
    for repo in manifest["repos"]:
        path = repo_path(dest, repo["path"])
        if not path.exists():
            errors.append(f"Missing repo path: {path}")
            continue
        if not (path / ".git").exists():
            errors.append(f"Not a git repo: {path}")
            continue
        try:
            branch = current_branch(path)
        except subprocess.CalledProcessError as exc:
            errors.append(f"Failed to read branch for {path}: {exc}")
            continue
        expected = repo["branch"]
        if branch != expected:
            errors.append(f"Branch mismatch for {path}: expected {expected}, got {branch}")


def verify_paths(dest: Path, rel_paths, label: str, errors: list[str]):
    for rel in rel_paths:
        path = dest / rel
        if not path.exists():
            errors.append(f"Missing {label}: {path}")


def verify_secrets(dest: Path, manifest, startup_phase: bool, errors: list[str]):
    for secret in manifest.get("secrets", []):
        phases = secret.get("phases", [])
        if startup_phase is False and "startup" in phases:
            continue

        if secret["type"] == "file":
            path = dest / secret["path"]
            if secret.get("required") and not path.exists():
                errors.append(f"Missing secret file: {path}")
        elif secret["type"] == "env":
            if secret.get("required") and not os.environ.get(secret["env"]):
                errors.append(f"Missing required environment variable: {secret['env']}")
        elif secret["type"] == "env-or-file-key":
            value = os.environ.get(secret["env"])
            if not value:
                env_file = dest / secret["file"]
                value = parse_env_file(env_file).get(secret["key"])
            if secret.get("required") and not value:
                errors.append(
                    f"Missing secret value for {secret['name']} (env {secret['env']} or key {secret['key']} in {secret['file']})"
                )


def verify_services(manifest, requested_targets: list[str], errors: list[str]):
    targets_cfg = manifest.get("startup", {}).get("targets", {})
    for target in requested_targets:
        target_cfg = targets_cfg.get(target)
        if not target_cfg:
            errors.append(f"Unknown startup target in verification request: {target}")
            continue
        for check in target_cfg.get("healthchecks", []):
            if check["type"] == "http":
                try:
                    wait_for_http(check["url"], timeout_seconds=5, interval_seconds=1)
                except SystemExit as exc:
                    errors.append(str(exc))
            elif check["type"] == "container":
                result = subprocess.run(
                    ["docker", "inspect", "-f", "{{.State.Running}}", check["name"]],
                    text=True,
                    capture_output=True,
                )
                if result.returncode != 0 or result.stdout.strip() != "true":
                    errors.append(f"Container not running: {check['name']}")


def parse_args():
    parser = argparse.ArgumentParser(description="Verify restored workspace repos, data, secrets, assets, and optionally services")
    parser.add_argument("destination", help="Workspace directory to verify")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    parser.add_argument("--skip-large-assets", action="store_true", help="Skip large asset verification")
    parser.add_argument("--skip-secrets", action="store_true", help="Skip secret verification")
    parser.add_argument("--services", nargs="*", help="Verify service health for the given startup targets (default targets if flag passed without values)")
    return parser.parse_args()


def main():
    args = parse_args()
    dest = Path(args.destination).expanduser().resolve()
    manifest = load_manifest(Path(args.manifest))

    errors: list[str] = []
    verify_repos(dest, manifest, errors)
    verify_paths(dest, manifest["restore_paths"], "restore path", errors)

    if not args.skip_large_assets:
        verify_paths(dest, [asset["path"] for asset in manifest.get("large_assets", []) if asset.get("required")], "large asset", errors)

    if not args.skip_secrets:
        verify_secrets(dest, manifest, startup_phase=args.services is not None, errors=errors)

    if args.services is not None:
        targets = args.services or manifest.get("startup", {}).get("default_targets", [])
        verify_services(manifest, targets, errors)

    if errors:
        for error in errors:
            print(f"[ERROR] {error}", file=sys.stderr)
        raise SystemExit(1)

    print(f"Workspace verification passed: {dest}")


if __name__ == "__main__":
    main()
