#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parent
DEFAULT_MANIFEST = ROOT / "workspace_restore_manifest.json"


def load_manifest(path: Path):
    with path.open() as f:
        return json.load(f)


def repo_path(dest: Path, repo_rel_path: str) -> Path:
    return dest if repo_rel_path == "." else dest / repo_rel_path


def require_command(cmd: str):
    if shutil.which(cmd) is None:
        raise SystemExit(f"Required command not found: {cmd}")


def run(cmd, cwd: Path | None = None, capture_output: bool = False, env=None, shell: bool = False, check: bool = True):
    display = cmd if isinstance(cmd, str) else " ".join(cmd)
    prefix = f"[{cwd}] " if cwd else ""
    print(f"+ {prefix}{display}")
    if shell:
        return subprocess.run(
            ["bash", "-lc", cmd],
            cwd=str(cwd) if cwd else None,
            check=check,
            text=True,
            capture_output=capture_output,
            env=_merged_env(env),
        )
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=check,
        text=True,
        capture_output=capture_output,
        env=_merged_env(env),
    )


def _merged_env(extra):
    merged = os.environ.copy()
    if extra:
        merged.update(extra)
    return merged


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


def latest_remote_artifact(remote: str, prefix: str, extensions: Iterable[str]) -> str:
    result = run(["rclone", "lsf", "--files-only", remote], capture_output=True)
    candidates = []
    for line in result.stdout.splitlines():
        name = line.strip()
        if not name.startswith(prefix):
            continue
        if any(name.endswith(ext) for ext in extensions):
            candidates.append(name)
    if not candidates:
        raise SystemExit(f"No snapshot artifacts found in remote: {remote}")
    return sorted(candidates)[-1]


def download_artifact(remote: str, artifact_name: str, temp_dir: Path):
    artifact = temp_dir / artifact_name
    checksum = temp_dir / f"{artifact_name}.sha256"
    run(["rclone", "copyto", f"{remote}/{artifact_name}", str(artifact)])
    run(["rclone", "copyto", f"{remote}/{artifact_name}.sha256", str(checksum)])
    verify_checksum(artifact, checksum)
    return artifact


def decrypt_if_needed(artifact: Path, age_identity_file: str | None = None) -> Path:
    if artifact.suffix != ".age":
        return artifact
    require_command("age")
    identity = age_identity_file or os.environ.get("AGE_IDENTITY_FILE") or os.environ.get("SOPS_AGE_KEY_FILE")
    if not identity:
        raise SystemExit(
            "Encrypted artifact requires AGE_IDENTITY_FILE, SOPS_AGE_KEY_FILE, or --age-identity-file"
        )
    decrypted = artifact.with_suffix("")
    run(["age", "--decrypt", "-i", identity, "-o", str(decrypted), str(artifact)])
    return decrypted


def extract_snapshot(artifact: Path, extract_to: Path):
    run(["tar", "-xzf", str(artifact), "-C", str(extract_to)])


def remove_path(path: Path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def restore_paths(extract_root: Path, dest: Path, restore_list, only_missing: bool = False):
    for rel in restore_list:
        src = extract_root / rel
        target = dest / rel
        if not src.exists():
            raise SystemExit(f"Expected restore path missing from snapshot: {src}")
        if target.exists() and only_missing:
            print(f"Skip existing path: {rel}")
            continue
        if target.exists():
            remove_path(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            shutil.copytree(src, target)
        else:
            shutil.copy2(src, target)
        print(f"Restored {rel}")


def parse_env_file(path: Path) -> dict[str, str]:
    values = {}
    if not path.exists():
        return values
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def wait_for_http(url: str, timeout_seconds: int = 180, interval_seconds: int = 5):
    deadline = time.time() + timeout_seconds
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                if 200 <= response.status < 500:
                    return
        except Exception as exc:  # noqa: BLE001
            last_error = exc
        time.sleep(interval_seconds)
    raise SystemExit(f"HTTP check failed for {url}: {last_error}")
