---
name: workspace-backup-recovery
description: Create, inspect, and restore the workspace-critical snapshot using the bundled workspace backup and recovery scripts. Use when asked to back up local-only workspace data, upload snapshots to Drive, inspect what is included, or rebuild the workspace from git remotes plus the snapshot tar.
---

# Workspace Backup Recovery

Use this skill for the workspace-level backup and restore workflow.

The canonical backup/recovery implementation now lives in the project root at `workspace-portability/`.

This skill remains as an operator-friendly wrapper around those standalone scripts so recovery does not depend on pi.

## What this workflow does

The canonical portability workflow now covers:

> Note: after Spec 048 removed the obsolete in-repo `survival-infrastructure/llm/` directory, the large-assets flow now backs up only the standalone `llm/gemma` model directory. Any older references to `survival-infrastructure/llm/gemma` are stale unless explicitly marked historical.


1. restore source code from git remotes
2. restore critical local-only ignored data from a critical snapshot tarball
3. restore large runtime assets from a dedicated large-assets snapshot
4. materialize required secret files and startup-time env inputs
5. install repo dependencies
6. optionally start canonical runtime services and verify them

The critical snapshot currently includes:

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

## Canonical files

The canonical implementation lives in:

- `workspace-portability/bootstrap-host.sh`
- `workspace-portability/create-snapshot.sh`
- `workspace-portability/create-large-assets-snapshot.sh`
- `workspace-portability/create-all-snapshots.sh`
- `workspace-portability/restore-workspace.sh`
- `workspace-portability/materialize-secrets.sh`
- `workspace-portability/hydrate-large-assets.sh`
- `workspace-portability/setup-workspace.sh`
- `workspace-portability/start-services.sh`
- `workspace-portability/full-restore.sh`
- `workspace-portability/verify-workspace.sh`
- `workspace-portability/test-restore.sh`
- `workspace-portability/workspace_restore_manifest.json`
- `workspace-portability/README.md`
- `workspace-portability/PORTABILITY_PLAN.md`

The skill directory keeps thin compatibility wrappers plus the audit/recovery notes.

## Preferred skill entrypoints

Create the critical snapshot:

```bash
./create-snapshot.sh
```

Restore repos + critical state:

```bash
./restore-workspace.sh /path/to/restored-workspace
```

For the full canonical flow, run the project-root scripts directly from `workspace-portability/`, especially `./full-restore.sh`.

The skill wrappers delegate to the canonical standalone scripts under `workspace-portability/`.

## Common commands

Create the critical snapshot and upload it to Drive:

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

- The canonical scripts operate from `workspace-portability/` in the workspace root.
- Snapshot creation uses `backup-tool/backup.sh` from the workspace.
- Restore uses `workspace-portability/workspace_restore_manifest.json` by default.
- The snapshot currently uploads to `workspace:workspace-critical-snapshot` using `rclone`.
- The latest local snapshot is stored under `/home/anupam/Desktop/backup_data/workspace-critical-snapshot/`.

## Safety notes

- `restore_workspace.py` is for disaster recovery / workspace replication.
- It fetches/clones repos, checks out the configured branch, and hard-resets to the configured remote branch.
- It may overwrite existing restored data paths.
- Environment rebuild, startup, and verification are available via the canonical scripts in `workspace-portability/`.
- Full setup still avoids restoring rebuildable directories like `.venv`, `node_modules`, caches, and logs from the critical snapshot; those are recreated by `setup-workspace.sh`.

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

The current Drive remote is still plain Google Drive, not `rclone crypt`, but the canonical snapshot scripts now support optional `age` encryption for offsite uploads. If encryption is not enabled, treat uploaded snapshots as sensitive.
