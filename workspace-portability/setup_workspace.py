#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from portability_lib import DEFAULT_MANIFEST, load_manifest, run


def parse_args():
    parser = argparse.ArgumentParser(description="Install per-repo dependencies for a restored workspace")
    parser.add_argument("destination", help="Workspace directory")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    parser.add_argument("--step", action="append", dest="steps", help="Specific setup step name to run (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    parser.add_argument("--continue-on-error", action="store_true", help="Continue running later steps after a failure")
    return parser.parse_args()


def main():
    args = parse_args()
    dest = Path(args.destination).expanduser().resolve()
    manifest = load_manifest(Path(args.manifest))

    failures: list[str] = []
    wanted = set(args.steps or [])

    for step in manifest.get("setup_steps", []):
        if wanted and step["name"] not in wanted:
            continue

        missing = [cmd for cmd in step.get("required_commands", []) if shutil.which(cmd) is None]
        if missing:
            msg = f"Skipping {step['name']}: missing commands {', '.join(missing)}"
            if step.get("optional"):
                print(msg)
                continue
            failures.append(msg)
            if not args.continue_on_error:
                break
            continue

        cwd = dest / step["cwd"]
        if not cwd.exists():
            msg = f"Setup cwd missing for {step['name']}: {cwd}"
            if step.get("optional"):
                print(msg)
                continue
            failures.append(msg)
            if not args.continue_on_error:
                break
            continue

        print(f"== setup step: {step['name']} ==")
        for command in step["commands"]:
            if args.dry_run:
                print(f"[dry-run] [{cwd}] {command}")
                continue
            try:
                run(command, cwd=cwd, shell=True)
            except Exception as exc:  # noqa: BLE001
                msg = f"Step failed [{step['name']}]: {exc}"
                if step.get("optional"):
                    print(msg)
                    break
                failures.append(msg)
                if not args.continue_on_error:
                    raise SystemExit(msg) from exc
                break

    if failures:
        for failure in failures:
            print(f"[ERROR] {failure}")
        raise SystemExit(1)

    print(f"Workspace setup complete: {dest}")


if __name__ == "__main__":
    main()
