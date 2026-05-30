---
name: workspace-backup-recovery
description: Create, inspect, and restore the workspace-critical snapshot using the bundled workspace backup and recovery scripts. Use when asked to back up local-only workspace data, upload snapshots to Drive, inspect what is included, or rebuild the workspace from git remotes plus the snapshot tar.
---

# Workspace Backup Recovery

Use this skill for the workspace-level backup and restore workflow.

This skill is fully self-contained. The backup scripts, restore script, manifest, and documentation are bundled in this skill directory rather than the project root.

## What this workflow does

The workspace recovery strategy has two parts:

1. restore source code from git remotes
2. restore critical local-only ignored data from a single snapshot tarball

The snapshot currently includes:

- `survival-infrastructure/data`
- `survival-infrastructure/data-prod`
- `survival-infrastructure/data_prod_copy`
- `survival-infrastructure/.runtime-data`
- `survival-infrastructure/.env`
- `feed_analyser/backend/data.db`
- `feed_analyser/backend/raw_data`
- `feed_analyser/backend/archive`
- `hermes/.hermes-data`

The restore flow recreates repos from `workspace_restore_manifest.json`, then restores those local-only paths from the snapshot.

## Bundled files

The skill directory contains:

- `create-snapshot.sh`
- `restore-workspace.sh`
- `create_workspace_critical_snapshot.sh`
- `restore_workspace.py`
- `workspace_restore_manifest.json`
- `WORKSPACE_BACKUP_AUDIT.md`
- `WORKSPACE_BACKUP_RECOVERY.md`

## Preferred skill entrypoints

Create a snapshot:

```bash
./create-snapshot.sh
```

Restore a workspace:

```bash
./restore-workspace.sh /path/to/restored-workspace
```

The wrappers call the bundled implementations in this same directory:

- `./create_workspace_critical_snapshot.sh`
- `./restore_workspace.py`

## Common commands

Create a local snapshot and upload it to Drive:

```bash
./create-snapshot.sh
```

Create a local snapshot only:

```bash
UPLOAD_TO_DRIVE=false ./create-snapshot.sh
```

Dry-run snapshot creation:

```bash
UPLOAD_TO_DRIVE=false ./create-snapshot.sh --dry-run
```

Restore the latest snapshot from Drive:

```bash
./restore-workspace.sh /path/to/restored-workspace
```

Restore a specific artifact from Drive:

```bash
./restore-workspace.sh \
  /path/to/restored-workspace \
  --artifact workspace_critical_snapshot_YYYYMMDD_HHMMSS.tar.gz
```

Restore from an already-downloaded local tarball:

```bash
./restore-workspace.sh \
  /path/to/restored-workspace \
  --skip-download \
  --local-artifact /path/to/workspace_critical_snapshot_YYYYMMDD_HHMMSS.tar.gz
```

## Operational expectations

- The bundled scripts operate on the current workspace root resolved relative to this skill directory.
- Snapshot creation uses `backup-tool/backup.sh` from the workspace.
- Restore uses the bundled `workspace_restore_manifest.json` by default.
- The snapshot currently uploads to `workspace:workspace-critical-snapshot` using `rclone`.
- The latest local snapshot is stored under `/home/anupam/Desktop/backup_data/workspace-critical-snapshot/`.

## Safety notes

- `restore_workspace.py` is for disaster recovery / workspace replication.
- It fetches/clones repos, checks out the configured branch, and hard-resets to the configured remote branch.
- It may overwrite existing restored data paths.
- It does **not** restore `.venv`, `node_modules`, caches, or GGUF model files.

## When to inspect the bundled references

Read the bundled files when you need to:

- change what is included in the snapshot
- change repo remotes or branches for restore
- audit what data is intentionally excluded from git
- debug Drive upload/download behavior
- confirm exactly which paths are restored

Important references:

- `WORKSPACE_BACKUP_RECOVERY.md`
- `WORKSPACE_BACKUP_AUDIT.md`
- `workspace_restore_manifest.json`
- `create_workspace_critical_snapshot.sh`
- `restore_workspace.py`

## Security note

The current Drive remote is documented as plain Google Drive, not `rclone crypt`, so treat uploaded snapshots as sensitive.
