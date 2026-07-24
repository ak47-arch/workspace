---
name: vscode-git-viewer-fix
description: Fix the VS Code SCM/Git viewer when repos stop showing up in the Source Control panel. Run this when repos are missing from the git view.
disable-model-invocation: true
---

# VS Code Git Viewer Fix

When the Source Control panel stops showing all your git repos, the root cause is almost always corrupted VS Code extension state — either the SCM repositories view got hidden, or the Git extension cache is stuck in a re-scan loop.

## Quick Fix

Run this and then **reload VS Code** (`Ctrl+Shift+P` → "Developer: Reload Window"):

```bash
python3 << 'EOF'
import sqlite3, json, os

# 1. Unhide the SCM repositories view (global)
gconn = sqlite3.connect(os.path.expanduser("~/.config/Code/User/globalStorage/state.vscdb"))
gc = gconn.cursor()
gc.execute("SELECT value FROM ItemTable WHERE key = 'workbench.scm.views.state.hidden'")
row = gc.fetchone()
if row:
    data = json.loads(row[0])
    for item in data:
        if item['id'] == 'workbench.scm.repositories':
            item['isHidden'] = False
    gc.execute("UPDATE ItemTable SET value = ? WHERE key = ?", (json.dumps(data), 'workbench.scm.views.state.hidden'))
gconn.commit()
gconn.close()

# 2. Clear corrupted git cache (global)
gconn2 = sqlite3.connect(os.path.expanduser("~/.config/Code/User/globalStorage/state.vscdb"))
gc2 = gconn2.cursor()
gc2.execute("DELETE FROM ItemTable WHERE key = 'vscode.git'")
gconn2.commit()
gconn2.close()

# 3. Find the workspace storage hash for this workspace
ws_dir = os.path.expanduser("~/.config/Code/User/workspaceStorage/")
target = os.path.realpath(os.getcwd())
ws_hash = None
for d in os.listdir(ws_dir):
    meta = os.path.join(ws_dir, d, "workspace.json")
    if os.path.isfile(meta):
        with open(meta) as f:
            try:
                if json.load(f).get("folder", "").replace("file://", "") == target:
                    ws_hash = d
                    break
            except:
                pass

if ws_hash:
    # 4. Clear SCM view state
    wconn = sqlite3.connect(os.path.join(ws_dir, ws_hash, "state.vscdb"))
    wc = wconn.cursor()
    for key in ["workbench.scm.views.state", "scm.viewState2", "scm:view:visibleRepositories"]:
        wc.execute("DELETE FROM ItemTable WHERE key = ?", (key,))
    wconn.commit()
    wconn.close()
    print(f"Fixed workspace: {target}")
else:
    print(f"Could not find workspace storage for: {target}")

print("Done. Reload VS Code now.")
EOF
```

## What this fixes

| Symptom | Cause |
|---------|-------|
| Repos missing from SCM panel | `workbench.scm.repositories` view is hidden |
| Git extension thrashing (constant scanning) | Corrupted `vscode.git` cache |
| Only a few repos show up | Stale `scm:view:visibleRepositories` state |

## Prevent recurrence

The `git.repositoryScanMaxDepth` setting in `.vscode/settings.json` should not exceed **2** when you have 30+ repos. A high depth combined with `autoRepositoryDetection: "subFolders"` causes the extension to re-scan constantly.

If you use this skill again and it doesn't help, check the Git extension log:
```bash
ls -t ~/.config/Code/logs/*/window1/exthost/vscode.git/Git.log | head -1
```
Look for repeated `git rev-parse --show-toplevel` calls — if there are thousands, the cache clear above is the fix.
