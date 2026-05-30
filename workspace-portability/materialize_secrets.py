#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path

from portability_lib import DEFAULT_MANIFEST, load_manifest, parse_env_file


def parse_args():
    parser = argparse.ArgumentParser(description="Verify or materialize secret files for a restored workspace")
    parser.add_argument("destination", help="Workspace directory")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    parser.add_argument("--secrets-dir", help="Directory containing file-based secret overrides, mirroring workspace-relative paths")
    parser.add_argument("--startup-phase", action="store_true", help="Also validate startup-time env/file-key requirements")
    parser.add_argument("--check-only", action="store_true", help="Validate without copying from --secrets-dir")
    return parser.parse_args()


def maybe_copy_secret_file(dest: Path, rel_path: str, secrets_dir: Path) -> bool:
    source = secrets_dir / rel_path
    target = dest / rel_path
    if source.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return True
    return False


def main():
    args = parse_args()
    dest = Path(args.destination).expanduser().resolve()
    manifest = load_manifest(Path(args.manifest))
    secrets_dir = Path(args.secrets_dir).expanduser().resolve() if args.secrets_dir else None

    errors: list[str] = []

    for secret in manifest.get("secrets", []):
        phases = secret.get("phases", [])
        if not args.startup_phase and "startup" in phases:
            continue

        stype = secret["type"]
        if stype == "file":
            path = dest / secret["path"]
            if path.exists():
                print(f"Secret file present: {path}")
                continue
            if secrets_dir and not args.check_only and maybe_copy_secret_file(dest, secret["path"], secrets_dir):
                print(f"Materialized secret file from secrets dir: {path}")
                continue
            if secret.get("required"):
                errors.append(f"Missing required secret file: {path}")
        elif stype == "env":
            if secret.get("required") and not os.environ.get(secret["env"]):
                errors.append(f"Missing required environment variable: {secret['env']}")
        elif stype == "env-or-file-key":
            value = os.environ.get(secret["env"])
            if not value:
                env_file = dest / secret["file"]
                if not env_file.exists() and secrets_dir and not args.check_only:
                    maybe_copy_secret_file(dest, secret["file"], secrets_dir)
                value = parse_env_file(env_file).get(secret["key"])
            if secret.get("required") and not value:
                errors.append(
                    f"Missing required secret value for {secret['name']} (env {secret['env']} or {secret['key']} in {secret['file']})"
                )

    if errors:
        for error in errors:
            print(f"[ERROR] {error}")
        raise SystemExit(1)

    print(f"Secret materialization/validation passed: {dest}")


if __name__ == "__main__":
    main()
