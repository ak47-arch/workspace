## Decision: Opensource Repo Manifest Registration Skill Design

**Status**: accepted
**Date**: 2026-07-27 23:02
**Project**: workspace-portability
**Session**: sessions/019fa31b-694b-7f94-ad00-bbc57a0c88df/session.jsonl

### Context

The workspace-portability project maintains a manifest (`workspace_restore_manifest.json`) that lists all repos to be backed up and restored. When a new opensource repo is cloned under `opensource/`, it must be manually added to the manifest — otherwise it gets missed by the backup pipeline. No automated mechanism existed for this registration.

### Problem

After cloning a new repo, users had to manually edit `workspace_restore_manifest.json` to add the correct path, remote URL, branch, and any extra remotes. This was error-prone and easy to forget. We needed a lightweight, deterministic way to register new opensource repos.

### Alternatives

1. **Automatic discovery script** — A script that scans `opensource/` for git repos not in the manifest and batch-adds them. Rejected because it adds scheduling/infrastructure complexity (cron, git hooks) and would either miss repos or over-detect.

2. **Git post-clone hook** — A hook that auto-registers after `git clone`. Rejected because hooks aren't portable and interfere with normal git workflows.

3. **Agent-invoked skill only** — A SKILL.md that instructs the agent what to do when a repo is cloned. Rejected because the agent can't discover newly cloned repos without the user explicitly calling the skill; at that point a deterministic script is simpler and doesn't depend on the agent being present.

4. **Deterministic script bundled with a skill (chosen)** — A small Python script that the user runs after cloning, bundled inside a skill directory with a SKILL.md. No agent dependency, no infrastructure, zero discoverability problem.

### Decision

A self-contained skill at `.agents/skills/manifest-add-repo/` with:

- `add-repo.py` — a Python script that takes a repo path, extracts git metadata (remote URL, branch, extra remotes), checks the manifest for duplicates, and appends to `additional_repos`.
- `SKILL.md` — documents the skill for both humans and the agent, with `disable-model-invocation: true` so it's user-invoked only.

### Rationale

- **Deterministic** — the script does exactly one thing and does it without agent interpretation
- **No infrastructure** — no cron, no hooks, no watch daemons
- **Discoverable** — user knows exactly when to call it (right after cloning)
- **Self-documenting** — the SKILL.md explains usage to any reader
- **Consistent with workspace-portability** — follows the same Python pattern used by `sync_repos.py` and `restore_workspace.py`
- **Zero dependency on the agent** — works whether or not the agent is running

### Consequences

- Users must remember to run the script after cloning. The SKILL.md serves as the reminder.
- The manifest stays in sync with what's actually on disk, but only for repos the user explicitly registers.
- Existing manifest entries are never modified — only new ones are appended.
- The script is scoped to adding to `additional_repos`; core `repos` section changes are still manual (intentional, since core repos change rarely).

### Revision triggers

- If a manifest format v4 introduces structural changes to repo entries (e.g., new required fields), the script must be updated.
- If workspace-portability adds a git-post-clone mechanism that auto-registers, this skill becomes redundant.
- If the skill pattern in `.agents/skills/` changes significantly (e.g., new frontmatter requirements).