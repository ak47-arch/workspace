#!/usr/bin/env python3

from __future__ import annotations

import argparse
import tempfile
from pathlib import Path

from portability_lib import (
    DEFAULT_MANIFEST,
    decrypt_if_needed,
    download_artifact,
    extract_snapshot,
    latest_remote_artifact,
    load_manifest,
    require_command,
    restore_paths,
    verify_checksum,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Restore or verify large workspace assets")
    parser.add_argument("destination", help="Workspace directory")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Path to restore manifest JSON")
    parser.add_argument("--snapshot-remote", help="Override large-assets snapshot remote")
    parser.add_argument("--artifact", help="Specific artifact file name to restore")
    parser.add_argument("--skip-download", action="store_true", help="Use existing local artifact from --local-artifact")
    parser.add_argument("--local-artifact", help="Path to a local large-assets snapshot")
    parser.add_argument("--age-identity-file", help="Identity file used to decrypt .age artifacts")
    parser.add_argument("--force", action="store_true", help="Restore assets even if the target paths already exist")
    parser.add_argument("--check-only", action="store_true", help="Only verify that required large assets exist")
    return parser.parse_args()


def main():
    args = parse_args()
    dest = Path(args.destination).expanduser().resolve()
    manifest = load_manifest(Path(args.manifest))
    assets = manifest.get("large_assets", [])
    missing = [asset for asset in assets if asset.get("required") and not (dest / asset["path"]).exists()]

    if args.check_only:
        if missing:
            for asset in missing:
                print(f"[ERROR] Missing large asset: {dest / asset['path']}")
            raise SystemExit(1)
        print(f"Large asset verification passed: {dest}")
        return

    if not missing and not args.force:
        print(f"Large assets already present: {dest}")
        return

    require_command("tar")
    snapshot_cfg = manifest["large_assets_snapshot"]
    remote = args.snapshot_remote or snapshot_cfg["remote"]

    if not args.skip_download:
        require_command("rclone")

    with tempfile.TemporaryDirectory(prefix="workspace-large-assets-") as tmp:
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
            print(f"Using remote large-assets snapshot: {artifact_name}")
            artifact = download_artifact(remote, artifact_name, tmpdir)

        artifact = decrypt_if_needed(artifact, args.age_identity_file)

        extract_dir = tmpdir / "extract"
        extract_dir.mkdir(parents=True, exist_ok=True)
        extract_snapshot(artifact, extract_dir)

        snapshot_root = extract_dir / snapshot_cfg["extract_root"]
        if not snapshot_root.exists():
            raise SystemExit(f"Large-assets snapshot root missing after extraction: {snapshot_root}")

        restore_paths(snapshot_root, dest, [asset["snapshot_path"] for asset in assets], only_missing=not args.force)

    print(f"Large assets hydrated at: {dest}")


if __name__ == "__main__":
    main()
