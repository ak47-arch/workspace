---
name: manifest-add-repo
description: Register a newly cloned opensource repo in the workspace-portability manifest so it gets backed up and restored.
disable-model-invocation: true
---

# Manifest Add Repo

## Summary

After cloning a new repo under `opensource/`, run this script to register it in
`workspace-portability/workspace_restore_manifest.json`. Without this, the new
repo won't be picked up by backup/restore operations.

The script is deterministic — it checks the repo, extracts git metadata, and
appends an entry to the manifest. It does nothing if the repo is already
registered.

## Usage

```bash
# From workspace root
python3 .agents/skills/manifest-add-repo/add-repo.py opensource/new-repo
```

## What it does

1. Verifies the path exists and is a git repository
2. Reads the current branch, primary remote URL, and any extra remotes
3. Checks the manifest (`workspace-portability/workspace_restore_manifest.json`)
   for an existing entry at the same path
4. If not found, appends a new entry to `additional_repos` and saves
5. Sorts the entries alphabetically by path

## Example

```bash
$ git clone https://github.com/someone/awesome-tool.git opensource/awesome-tool
$ python3 .agents/skills/manifest-add-repo/add-repo.py opensource/awesome-tool
✓ Added 'opensource/awesome-tool' to workspace-portability/workspace_restore_manifest.json
  Entry:
    path:             opensource/awesome-tool
    primary_remote:   origin
    clone_url:        https://github.com/someone/awesome-tool.git
    branch:           main
```

## Location

- Script: `.agents/skills/manifest-add-repo/add-repo.py`
- Manifest: `workspace-portability/workspace_restore_manifest.json`