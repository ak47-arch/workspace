# Workspace Backup and Recovery

Date: 2026-05-24
Workspace root: `/home/anupam/Desktop/workspace`
Skill location: `/home/anupam/Desktop/workspace/.pi/skills/workspace-backup-recovery`

This document describes the current backup and recovery setup for the workspace.

## What is backed up

The workspace backup does **not** try to archive every repo checkout artifact. It focuses on:

1. source code recoverable from git remotes
2. critical local-only data that is ignored by git and would otherwise be lost

### Recovered from git remotes

These repositories are restored from git during recovery:

- workspace root repo
- `backup-tool`
- `emotional_architecture`
- `feed_analyser`
- `hermes`
- `llm`
- `survival-infrastructure`

### Recovered from the snapshot tar

These local-only paths are restored from the snapshot:

- `survival-infrastructure/data`
- `survival-infrastructure/data-prod`
- `survival-infrastructure/data_prod_copy`
- `survival-infrastructure/.runtime-data`
- `survival-infrastructure/.env`
- `feed_analyser/backend/data.db`
- `feed_analyser/backend/raw_data`
- `feed_analyser/backend/archive`
- `hermes/.hermes-data`

## Snapshot creation

Snapshot creation script:

- `create_workspace_critical_snapshot.sh`

Preferred wrapper:

- `create-snapshot.sh`

What it does:

1. stages the critical local-only data into a temporary snapshot directory
2. excludes obvious cache junk inside `hermes/.hermes-data`
3. creates a **single tar.gz** using `backup-tool/backup.sh`
4. keeps only the latest local snapshot (`--retention 1`)
5. uploads the tar and checksum to Google Drive via `rclone`

### Hermes exclusions

The snapshot intentionally excludes the following Hermes cache/runtime paths to keep the backup smaller:

- `.hermes-data/.cache`
- `.hermes-data/.npm`
- `.hermes-data/audio_cache`
- `.hermes-data/image_cache`
- `.hermes-data/logs`
- `.hermes-data/cache`
- `.hermes-data/ollama_cloud_models_cache.json`
- `.hermes-data/models_dev_cache.json`
- `.hermes-data/.update_check`

### Local snapshot location

- `/home/anupam/Desktop/backup_data/workspace-critical-snapshot/`

Current behavior:
- one local tar retained
- one matching `.sha256` retained

### Cloud upload location

The snapshot script currently uploads to:

- `workspace:workspace-critical-snapshot`

This is the currently configured `rclone` Google Drive remote.

## Snapshot commands

Run from the skill directory:

```bash
./create-snapshot.sh
```

Or call the bundled implementation directly:

```bash
./create_workspace_critical_snapshot.sh
```

Useful variants:

```bash
# Create local snapshot only, skip Drive upload
UPLOAD_TO_DRIVE=false ./create-snapshot.sh
```

```bash
# Use a different rclone remote/path
RCLONE_REMOTE='workspace:workspace-critical-snapshot' ./create-snapshot.sh
```

```bash
# Dry-run
UPLOAD_TO_DRIVE=false ./create-snapshot.sh --dry-run
```

## Recovery

Recovery script:

- `restore_workspace.py`

Preferred wrapper:

- `restore-workspace.sh`

Restore manifest:

- `workspace_restore_manifest.json`

What recovery does:

1. finds the latest snapshot tar on Drive
2. downloads the tar and checksum
3. verifies the checksum
4. extracts the snapshot
5. clones/fetches all repos into the right workspace layout
6. checks out the configured branch for each repo
7. restores the local-only data back into the correct paths

### Restore command

```bash
./restore-workspace.sh /path/to/restored-workspace
```

### Restore a specific snapshot

```bash
./restore-workspace.sh \
  /path/to/restored-workspace \
  --artifact workspace_critical_snapshot_20260524_213956.tar.gz
```

### Restore from an already downloaded local tar

```bash
./restore-workspace.sh \
  /path/to/restored-workspace \
  --skip-download \
  --local-artifact /home/anupam/Desktop/backup_data/workspace-critical-snapshot/workspace_critical_snapshot_20260524_213956.tar.gz
```

### Run the Python restore script directly

```bash
python3 ./restore_workspace.py /path/to/restored-workspace
```

## Recovery assumptions

The restore flow depends on these remaining valid:

- the repo URLs in `workspace_restore_manifest.json`
- the configured default branches in `workspace_restore_manifest.json`
- the snapshot existing in Google Drive
- `git`, `python3`, `tar`, and `rclone` being installed on the recovery machine

If a repo remote or branch changes later, update the manifest.

## Important operational notes

- The restore script is designed for **disaster recovery / workspace replication**.
- It is intentionally convergent and may overwrite existing restored data paths.
- It hard-resets repositories to the configured remote branch.
- It does **not** restore:
  - `.venv`
  - `node_modules`
  - caches
  - GGUF model files

Those are expected to be recreated or restored separately if needed.

## Current known limitation

The current cloud remote is plain Google Drive remote `workspace:`.
That means Drive-side storage is not additionally encrypted by `rclone crypt`.
Since the snapshot contains `.env`, cookies, state files, and local databases, moving later to an encrypted `crypt` remote would be preferable.

## Bundled files in this skill

- `SKILL.md`
- `WORKSPACE_BACKUP_AUDIT.md`
- `WORKSPACE_BACKUP_RECOVERY.md`
- `create-snapshot.sh`
- `restore-workspace.sh`
- `create_workspace_critical_snapshot.sh`
- `restore_workspace.py`
- `workspace_restore_manifest.json`

## Recommended recurring workflow

1. run the snapshot script after meaningful local-data changes
2. confirm the tar and `.sha256` exist locally
3. confirm the files appear in Drive via `rclone ls workspace:workspace-critical-snapshot`
4. periodically test restore into a scratch directory
