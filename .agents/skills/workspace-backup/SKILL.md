---
name: workspace-backup
description: Perform a round of backup for the workspace using the critical snapshot pipeline.
disable-model-invocation: true
---

# Workspace Backup

## Summary

Run a backup:

```bash
cd /home/anupam/Desktop/workspace/workspace-portability
./create_workspace_critical_snapshot.sh
```

This creates a local `.tar.gz` archive of runtime data (survival-infrastructure data, feed_analyser DB, hermes state, graphify-out dirs), uploads it to Google Drive (rclone) and GitHub Release, and prunes both local and remote old artifacts.

If anything fails, the full backup/restore infrastructure lives in `/home/anupam/Desktop/workspace/workspace-portability/` — see its `README.md` for the full picture.