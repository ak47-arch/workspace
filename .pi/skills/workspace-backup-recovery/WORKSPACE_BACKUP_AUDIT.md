# Workspace Remotes and Backup Audit

Date: 2026-05-24
Location audited: `/home/anupam/Desktop/workspace`

## Scope and method

This document summarizes:

1. The git remotes for each project in the workspace.
2. The local data that is **not committed / not pushed** because it is excluded by `.gitignore` or local git excludes.
3. Which ignored data should be treated as **must-back-up**, versus which ignored data is mostly **rebuildable**.

Method used:

- inspected all top-level git repositories in the workspace
- read repository `.gitignore` files
- checked `.git/info/exclude` where relevant
- checked current ignored paths with `git status --ignored --short`
- sampled actual local ignored data and sizes

## Current implementation status

This audit has now been turned into an active backup/recovery workflow bundled in the skill directory `.pi/skills/workspace-backup-recovery/`:

- critical local-only workspace data is captured by `create_workspace_critical_snapshot.sh`
- the snapshot is stored locally as a **single tar.gz** plus `.sha256`
- the latest snapshot is uploaded to Google Drive via `rclone`
- full workspace recovery is handled by `restore_workspace.py`
- repo remotes/branches and restore paths are defined in `workspace_restore_manifest.json`
- operational details are documented in `WORKSPACE_BACKUP_RECOVERY.md`

## Important top-level observation

The workspace root repo ignores all project directories:

- `/backup-tool/`
- `/emotional_architecture/`
- `/feed_analyser/`
- `/hermes/`
- `/llm/`
- `/survival-infrastructure/`

So the root workspace remote **does not back up the code inside those project folders**. Each nested project must be backed up via:
- its own git remote for code, and
- separate file backups for ignored local data.

---

## Git remotes

| Project | Remote name | URL |
|---|---|---|
| workspace root | origin | `https://github.com/ak47-arch/workspace.git` |
| backup-tool | origin | `https://github.com/ak47-arch/backup-tool.git` |
| emotional_architecture | origin | `https://github.com/ak47-arch/emotional_architecture.git` |
| feed_analyser | origin | `https://github.com/forthechemicals/forthechemicals_agentic_social_media.git` |
| hermes | origin | `https://github.com/ak47-arch/hermes.git` |
| hermes | upstream | `https://github.com/NousResearch/hermes-agent.git` |
| llm | origin | `https://github.com/ak47-arch/llamacpp_inference_server.git` |
| survival-infrastructure | incident-remote | `https://github.com/ak47-arch/survival-infrastructure.git` |

---

## Backup findings by repository

## 1) workspace root

### Ignore sources
- `.gitignore`

### What is ignored locally
- all nested project directories listed above
- root `.venv/` (~30M)
- Python caches / test artifacts

### Backup assessment
- **Must back up:** not at the root level, except possibly root-only local tooling if needed.
- **Low priority / rebuildable:** `.venv/`, `__pycache__/`, `.pytest_cache/`

### Notes
The important thing here is structural: the workspace repo is only a wrapper/meta repo. It does **not** contain the nested project source trees.

---

## 2) backup-tool

### Ignore sources
- no project `.gitignore` detected
- `.git/info/exclude` is default only

### Current ignored data detected
- none

### Backup assessment
- **No repository-specific ignored data detected**

---

## 3) emotional_architecture

### Ignore sources
- no project `.gitignore` detected
- `.git/info/exclude` is default only

### Current ignored data detected
- none

### Backup assessment
- **No repository-specific ignored data detected**

---

## 4) feed_analyser

### Ignore sources
- `feed_analyser/.gitignore`
- `feed_analyser/backend/.gitignore`
- `feed_analyser/frontend/.gitignore`

### Relevant ignore patterns
- Python envs and caches: `.venv/`, `venv/`, `__pycache__/`, `*.pyc`
- Node/build: `node_modules/`, `dist/`, `build/`
- Local DB/data: `backend/data.db`, `backend/raw_data/`, `backend/archive/`
- Broad content ignores: `*.json`, `*.txt`, `*.png`, `*.webm`
- Sensitive/local files: `*cookies*`, `.env`
- Logs: `*.log`

### Current ignored local data detected
- `.venv/` (~190M)
- `backend/venv/` (~313M)
- `frontend/node_modules/` (~155M)
- `frontend/dist/` (~244K)
- `backend/data.db` (~308K)
- `backend/raw_data/` (~852K, 5 files)
  - includes debug artifacts and cookies text
- `backend/archive/` (~260K, 14 files)
  - archived repost / twitter JSON files
- `.opencode/config.json` (~8K)
  - effectively ignored because `*.json` is ignored

### Backup assessment
**Must back up**
- `backend/data.db`
- `backend/raw_data/`
- `backend/archive/`
- any cookie/session material that is still needed operationally
- `.env` if present later
- `.opencode/config.json` only if it contains local workflow settings you care about

**Low priority / rebuildable**
- `.venv/`
- `backend/venv/`
- `frontend/node_modules/`
- `frontend/dist/`
- caches and logs

### Notes
This repo has the clearest case of useful ignored application data. The SQLite DB, raw scrape inputs, archives, and cookie-related material are not on the remote and should be part of backups.

---

## 5) hermes

### Ignore sources
- `hermes/.gitignore`
- `hermes/ui-tui/.gitignore`
- `hermes/website/.gitignore`
- `hermes/.git/info/exclude`

### Relevant ignore patterns
From tracked `.gitignore` files:
- env files: `.env`, `.env.local`, etc.
- local data dirs: `data/`, `source-data/*`, `images/`, `wandb/`, `logs/`, `tmp/`
- generated assets/build output: `node_modules/`, `web/public/fonts/`, `web/public/ds-assets/`, `hermes_cli/web_dist/`, `hermes_cli/tui_dist/*`
- local config: `cli-config.yaml`
- private keys: `*.ppk`, `*.pem`, `privvy*`

From local repo exclude only:
- `.hermes-data/`

### Current ignored local data detected
- `.hermes-data/` (~36M, 629 files)
  - includes:
    - `.hermes-data/config.yaml`
    - `.hermes-data/.env`
    - `.hermes-data/.hermes_history`
    - `.hermes-data/state.db`, `state.db-shm`, `state.db-wal`
    - `.hermes-data/logs/`
    - `.hermes-data/cache/model_catalog.json`
    - `.hermes-data/skills/` (~7.8M)

### Backup assessment
**Must back up**
- `.hermes-data/config.yaml`
- `.hermes-data/.env`
- `.hermes-data/.hermes_history`
- `.hermes-data/state.db*`
- `.hermes-data/skills/` if it contains local curated state you need
- any local keys/config files matching ignored patterns, if present

**Low priority / rebuildable**
- most logs
- node/web build outputs
- caches

### Notes
This is important because `.hermes-data/` is **not ignored by the tracked `.gitignore`**; it is ignored only in local `.git/info/exclude`. That means it is definitely local-only and not pushed anywhere unless backed up separately.

---

## 6) llm

### Ignore sources
- `llm/.gitignore`

### Relevant ignore patterns
- `.venv/`
- `__pycache__/`
- `gemma/*.gguf`
- `Free_Test_Data_10MB_WAV.wav`

### Current ignored local data detected
- `.venv/` (~127M)
- `gemma/` model files (~16G total)
  - `google_gemma-4-E2B-it-IQ2_M.gguf` (~2.5G)
  - `google_gemma-4-E2B-it-Q4_K_M.gguf` (~3.3G)
  - `gemma-4-E4B-it-UD-IQ2_M.gguf` (~3.3G)
  - `google_gemma-4-E4B-it-Q4_K_M.gguf` (~5.1G)
  - `mmproj-google_gemma-4-E2B-it-f16.gguf` (~940M)
  - `mmproj-google_gemma-4-E4B-it-f16.gguf` (~945M)
- `tmp/Free_Test_Data_10MB_WAV.wav` (~11M)
- caches / `__pycache__/`

### Backup assessment
**Must back up if local availability matters**
- `gemma/*.gguf` model files

**Usually not critical but expensive to recreate**
- model weights are often redownloadable, but because they total ~16G, backing them up can save time/bandwidth and preserve exact versions used locally

**Low priority / rebuildable**
- `.venv/`
- caches
- sample WAV file

### Notes
This repo's main ignored payload is large model weight data. It may not be unique, but it is large and operationally valuable.

---

## 7) survival-infrastructure

### Ignore sources
- `survival-infrastructure/.gitignore`

### Relevant ignore patterns
- `data/`
- `data-prod/`
- `data_prod_copy/`
- `data*`
- `.runtime-data/`
- `.env`
- `.app.pid`
- `.app.log`
- `vendors/`
- `llm/gemma/*.gguf`
- `.venv/`
- test and temp outputs

### Current ignored local data detected
- `data/` (~7.4M)
  - includes events, extractions, jobs, people, photos, impulses, instructions
  - sampled counts:
    - `data/events/` 19 files
    - `data/people/` 18 files
    - `data/jobs/` 28 files
    - `data/instructions/uploads/` 3 files
- `data-prod/` (~228K, 42 files)
- `data_prod_copy/` (~640K, 84 files)
- `.runtime-data/` (~400K)
- `.env` (~4K)
- `.app.log` (~8K)
- `vendors/` (~91M)
- `llm/gemma/` (~14G)
- `.venv/` (~177M)

### Backup assessment
**Must back up**
- `data/`
- `data-prod/`
- `data_prod_copy/`
- `.runtime-data/`
- `.env` (securely)
- any local model files in `llm/gemma/` if those exact local weights matter

**Maybe back up depending on purpose**
- `vendors/` if it contains local vendored code or third-party source not trivially reproducible

**Low priority / rebuildable**
- `.venv/`
- `.app.pid`
- most logs
- caches / `__pycache__/`

### Notes
This is the strongest backup candidate in the workspace. The broad `data*` ignore pattern means a lot of operational data is intentionally excluded from git and will not be pushed.

---

## Consolidated backup priority list

## Highest priority: unique local data and secrets

Back these up first:

- `feed_analyser/backend/data.db`
- `feed_analyser/backend/raw_data/`
- `feed_analyser/backend/archive/`
- `feed_analyser` cookie/session files
- `hermes/.hermes-data/`
- `survival-infrastructure/data/`
- `survival-infrastructure/data-prod/`
- `survival-infrastructure/data_prod_copy/`
- `survival-infrastructure/.runtime-data/`
- all `.env` files and local config files containing secrets

## Medium priority: expensive local assets

- `llm/gemma/*.gguf`
- `survival-infrastructure/llm/gemma/`
- possibly `survival-infrastructure/vendors/`

## Lowest priority: reproducible local environments / builds

These are not pushed, but generally do not need backup unless you want faster machine recovery:

- any `.venv/` / `venv/`
- `node_modules/`
- `dist/`, `build/`
- `__pycache__/`, `.pytest_cache/`
- logs
- pid files

---

## Recommended backup set for this workspace

If the goal is to preserve everything that is both local and valuable, the practical backup set is:

- `feed_analyser/backend/data.db`
- `feed_analyser/backend/raw_data/`
- `feed_analyser/backend/archive/`
- `feed_analyser/.opencode/` (optional)
- `hermes/.hermes-data/`
- `llm/gemma/`
- `survival-infrastructure/data/`
- `survival-infrastructure/data-prod/`
- `survival-infrastructure/data_prod_copy/`
- `survival-infrastructure/.runtime-data/`
- `survival-infrastructure/.env`
- any other `.env`, cookie, key, or local config files in ignored paths

## Final conclusion

The repositories with the most important non-pushed local data are:

1. `survival-infrastructure`
2. `feed_analyser`
3. `hermes`
4. `llm` (mostly large model files)

`backup-tool` and `emotional_architecture` currently do not show repository-specific ignored data that needs separate backup.
