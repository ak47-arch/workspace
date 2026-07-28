---
name: manifest-add-repo
description: Scans `opensource/` for git repos and adds any that exist on disk but are missing from the workspace restore manifest. Use when new repos have been cloned under `opensource/` and need to be registered for backup/restore operations.
---

# Manifest Add Repo

## Summary

Deterministically scans `opensource/` for git repos, compares them against
`workspace-portability/workspace_restore_manifest.json`, and adds any repos
that exist on disk but are missing from the manifest.

Without this, newly cloned repos under `opensource/` won't be picked up by
backup/restore operations.

## Usage

```bash
# From workspace root — auto-discovers missing repos
python3 .agents/skills/manifest-add-repo/add-repo.py

# With explicit manifest path
python3 .agents/skills/manifest-add-repo/add-repo.py --manifest /path/to/workspace_restore_manifest.json
```

No arguments needed — the script reads the manifest, scans `opensource/`, and
adds whatever is missing.

## What it does

1. Loads the manifest (`workspace-portability/workspace_restore_manifest.json`)
2. Scans every subdirectory under `opensource/` that contains a `.git` directory
3. For each repo not already registered (in `repos` or `additional_repos`),
   reads its git metadata: current branch, primary remote URL, and extra remotes
4. Appends a new entry to `additional_repos` for each missing repo
5. Sorts `additional_repos` alphabetically by path and saves

## Example

```bash
$ git clone https://github.com/someone/awesome-tool.git opensource/awesome-tool
$ python3 .agents/skills/manifest-add-repo/add-repo.py
✓ Added 1 missing repo(s) to workspace-portability/workspace_restore_manifest.json
  - opensource/awesome-tool
    primary_remote:   origin
    clone_url:        https://github.com/someone/awesome-tool.git
    branch:           main
```

## Location

- Script: `.agents/skills/manifest-add-repo/add-repo.py`
- Manifest: `workspace-portability/workspace_restore_manifest.json`