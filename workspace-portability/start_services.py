#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

from portability_lib import DEFAULT_MANIFEST, load_manifest, parse_env_file, run, wait_for_http


def parse_args():
    parser = argparse.ArgumentParser(description="Start canonical workspace runtime services")
    parser.add_argument("destination", help="Workspace directory")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    parser.add_argument("--target", action="append", dest="targets", help="Startup target to launch (repeatable)")
    parser.add_argument("--skip-verify", action="store_true", help="Skip post-start health checks")
    return parser.parse_args()


def resolve_targets(manifest, requested: list[str] | None):
    startup = manifest.get("startup", {})
    targets = requested or startup.get("default_targets", [])
    available = startup.get("targets", {})
    for target in targets:
        if target not in available:
            raise SystemExit(f"Unknown startup target: {target}")
    return targets


def ensure_prereqs(dest: Path, manifest, targets: list[str]):
    startup = manifest["startup"]
    asset_map = {asset["name"]: asset for asset in manifest.get("large_assets", [])}
    env_file_values = parse_env_file(dest / "survival-infrastructure/.env")

    for target in targets:
        cfg = startup["targets"][target]
        for env_var in cfg.get("required_env", []):
            if env_var == "SURVIVAL_LLAMA_CPP_DIR":
                value = os.environ.get(env_var) or env_file_values.get(env_var)
            else:
                value = os.environ.get(env_var)
            if not value:
                raise SystemExit(f"Missing required environment variable for startup target {target}: {env_var}")
        for asset_name in cfg.get("required_large_assets", []):
            asset = asset_map.get(asset_name)
            if not asset:
                raise SystemExit(f"Unknown large asset referenced by startup target {target}: {asset_name}")
            if not (dest / asset["path"]).exists():
                raise SystemExit(f"Missing required large asset for startup target {target}: {dest / asset['path']}")


def verify_targets(manifest, targets: list[str]):
    for target in targets:
        for check in manifest["startup"]["targets"][target].get("healthchecks", []):
            if check["type"] == "http":
                wait_for_http(check["url"], timeout_seconds=180, interval_seconds=5)
            elif check["type"] == "container":
                result = subprocess.run(
                    ["docker", "inspect", "-f", "{{.State.Running}}", check["name"]],
                    text=True,
                    capture_output=True,
                )
                if result.returncode != 0 or result.stdout.strip() != "true":
                    raise SystemExit(f"Container not running after startup: {check['name']}")


def main():
    args = parse_args()
    dest = Path(args.destination).expanduser().resolve()
    manifest = load_manifest(Path(args.manifest))
    targets = resolve_targets(manifest, args.targets)
    ensure_prereqs(dest, manifest, targets)

    startup = manifest["startup"]
    cwd = dest / startup["cwd"]
    run(list(startup["command"]) + targets, cwd=cwd)

    if not args.skip_verify:
        verify_targets(manifest, targets)

    print(f"Services started successfully for targets: {' '.join(targets)}")


if __name__ == "__main__":
    main()
