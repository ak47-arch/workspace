# Themistocles Integration Analysis

> How the Debian 13 secondary system (`themistocles`, 192.168.0.122) can serve the workspace projects: Survival Infrastructure, LLM Inference Server, and Feed Analyser.

**Date:** 2026-06-06
**System:** Intel i3-2350M, 3.7 GB RAM, 454 GB SSD, Debian 13, Wi-Fi

---

## Section 1: Feasibility Assessment

### 1.1 LLM Inference Server — 🔴 RED (Not Practical)

The LLM server requires llama.cpp to load model weights into RAM and run inference.

| Factor | Requirement | Themistocles Reality |
|---|---|---|
| **Model RAM** | Active model `google_gemma-4-E4B-it-Q4_K_M.gguf` is **5.1 GB** on disk, needs ~5–6 GB in RAM at runtime | **3.7 GB total** (only 3.2 GB free) |
| **mmproj RAM** | `mmproj-google_gemma-4-E4B-it-f16.gguf` is **945 MB**, loaded alongside model | Already exceeds RAM budget |
| **CPU threads** | Config uses `threads: 8` for llama-server | Only 2 cores / 4 threads (2011-era) |
| **Inference speed** | Even E2B (3.3 GB) model would be slow on this CPU | Expect 10–30× slower than main machine |
| **Container runtime** | Docker/Podman required for containerized deployment | Not installed; would consume additional RAM |

Even the smallest model variant (E2B Q4 at 3.3 GB + 940 MB mmproj = ~4.2 GB) exceeds available RAM. Bare-metal Python could shave off container overhead, but the model still won't fit. **LLM inference on themistocles is not feasible with current models.**

Verdict: **Do not attempt to run the LLM inference server on themistocles.** Keep it on the main machine where it already runs.

---

### 1.2 Survival Infrastructure App — 🟡 YELLOW (Constrained but Feasible)

| Factor | Requirement | Themistocles Reality |
|---|---|---|
| **Python runtime** | Flask + requests + PyYAML (~50 MB) | Python 3.13.5 available ✅ |
| **App RAM** | Lightweight Flask app, ~50–150 MB idle | Plenty of headroom ✅ |
| **LLM dependency** | **Hard dependency** — extraction, validation, wiki synthesis all call LLM server | LLM server can't run locally; must remote-call main machine ❌→🟡 |
| **Data storage** | JSONL + JSON files under `./data/` | 454 GB SSD, only ~5 GB used ✅ |
| **Container runtime** | Docker/Podman for containerized deployment | Not installed; bare-metal `python app.py` works ✅ |
| **Network** | Must reach LLM server at `http://llm-inference-server:8012` | Can SSH tunnel to main machine's port 8012 🟡 |

The survival infra Flask app itself is lightweight. The blocker is the LLM dependency — it cannot run locally, but can be satisfied via an SSH tunnel to the main machine's inference server. Extraction latency would increase by network round-trip (~1–5 ms LAN), which is negligible compared to inference time (seconds to minutes).

**Key risk:** If the main machine is off or the SSH tunnel drops, all LLM-dependent operations (extraction, wiki synthesis, validation) fail. Capture-only mode still works.

Verdict: **Feasible as a secondary instance with remote LLM, assuming persistent SSH tunnel.**

---

### 1.3 Feed Analyser Backend — 🟢 GREEN (Good Fit)

| Factor | Requirement | Themistocles Reality |
|---|---|---|
| **Python runtime** | FastAPI + uvicorn + SQLite (~100 MB) | Python 3.13.5 available ✅ |
| **App RAM** | ~150–300 MB idle, more under load | 3.2 GB free — ample ✅ |
| **LLM dependency** | Ollama for classify/scout — **but has heuristic fallback** | Falls back gracefully without Ollama 🟢 |
| **SQLite DB** | `data.db` — zero-config, embedded | Works natively ✅ |
| **Directory watcher** | `watchdog` library, watches `raw_data/` for new JSON | Works natively ✅ |
| **Playwright** | `twitter_headless.py` needs Chromium browser | Installable via `pip install playwright && playwright install chromium` 🟡 |
| **Node.js** | Frontend needs Node.js/npm (Vite dev server) | Not installed; would need `apt install nodejs npm` 🟡 |
| **Container runtime** | Docker for sandbox, Dozzle, db-ui | Not installed; these are optional conveniences 🟡 |
| **Network** | API on port 8000, frontend on 5174 | Wi-Fi connected, accessible at 192.168.0.122 ✅ |

The feed analyser backend is the best fit. The classifier falls back to keyword heuristics when Ollama is unavailable, so it remains fully functional without any LLM. The github_scout also has heuristic fallback paths. The directory watcher can run as a persistent daemon, ingesting new data files automatically.

**Without Docker:** The runner sandbox (Alpine container for code evaluation) won't work, but this is a Phase 2 feature that isn't critical to the core ingestion→classify→scout pipeline. Dozzle and db-ui are monitoring conveniences that can be replaced with direct `sqlite3` queries and `journalctl`/log files.

Verdict: **Feed analyser backend (ingestion + classification + scouting) runs well on themistocles. The heuristic fallback makes it LLM-independent.**

---

### 1.4 Feed Analyser Frontend — 🟡 YELLOW (Constrained but Feasible)

| Factor | Requirement | Themistocles Reality |
|---|---|---|
| **Node.js** | Vite dev server, React build | Not installed; `apt install nodejs npm` adds ~200 MB 🟡 |
| **RAM** | Vite dev server ~200–400 MB | Fits in 3.2 GB free 🟡 |
| **Build time** | `npm install` + `npm run build` | Slow on i3-2350M but one-time cost 🟡 |

Verdict: **Installable but not essential.** The frontend can stay on the main machine and point to themistocles' backend API at `http://192.168.0.122:8000`.

---

### 1.5 Ingestion Scripts (Standalone) — 🟢 GREEN (Good Fit)

| Script | Dependencies | Themistocles Fit |
|---|---|---|
| `twitter_headless.py` | Playwright + Chromium | Installable, headless browser works on Debian ✅ |
| `youtube_cron.sh` | yt-dlp (Python package) | Works natively ✅ |
| `parse_twitter_archive.py` | Python stdlib + JSON | Works natively ✅ |

These scripts are designed to run offline/independently. They write JSON files to `raw_data/`, which the backend's directory watcher picks up.

Verdict: **Ideal for themistocles.** These are cron-friendly, need no containers, and decouple data collection from the development machine.

---

### 1.6 Summary Matrix

| Component | Rating | Reasoning |
|---|---|---|
| **LLM Inference Server** | 🔴 RED | Model weights (5.1 GB + 945 MB) exceed 3.7 GB RAM |
| **Survival Infra (bare-metal)** | 🟡 YELLOW | Works if tunneled to main machine's LLM; capture-only mode survives tunnel drops |
| **Survival Infra (containerized)** | 🔴 RED | No Docker installed; adding it wastes RAM for no benefit |
| **Feed Analyser Backend** | 🟢 GREEN | Python + SQLite + heuristic fallback = fully functional without LLM/Docker |
| **Feed Analyser Frontend** | 🟡 YELLOW | Needs Node.js install; optional — can run on main machine |
| **Feed Analyser Sandbox** | 🔴 RED | Requires Docker; non-essential Phase 2 feature |
| **Ingestion Scripts** | 🟢 GREEN | Designed for offline/independent execution; cron-friendly |
| **Backup / Data Mirror** | 🟢 GREEN | 454 GB SSD with 426 GB free; rsync works over SSH |

---

## Section 2: Recommended Deployment Scenarios

### Scenario A: "Ingestion Automation Node" ⭐ (Top Recommendation)

**What runs on themistocles:**
- Feed analyser backend (FastAPI on port 8000)
- Directory watcher daemon
- Ingestion cron jobs (`twitter_headless.py`, `youtube_cron.sh`)
- SQLite database (`data.db`)

**What stays on the main system:**
- LLM inference server (port 8012)
- Survival infrastructure (ports 5151/5152/5153)
- Feed analyser frontend (port 5174, pointing to `http://192.168.0.122:8000`)
- All Docker/Podman infrastructure

**How they communicate:**
```
Main Machine                               Themistocles (192.168.0.122)
┌─────────────────────────┐                ┌──────────────────────────────┐
│  Feed Analyser Frontend │───HTTP────────▶│  Feed Analyser Backend       │
│  (Vite :5174)           │                │  (FastAPI :8000)             │
│                          │                │  ├─ classify_worker (heur.)  │
│  LLM Inference Server   │                │  ├─ github_scout (heur.)     │
│  (:8012)                │                │  ├─ directory_watcher        │
│                          │                │  └─ data.db                 │
│  Survival Infra          │                │                              │
│  (:5151/5152/5153)      │                │  Cron jobs:                  │
│                          │                │  ├─ twitter_headless.py     │
│                          │                │  └─ youtube_cron.sh         │
└─────────────────────────┘                └──────────────────────────────┘
```

**Value provided:**
1. **Decoupled ingestion** — Scraping runs 24/7 on themistocles without tying up the main machine
2. **Always-on collection** — Twitter bookmarks and YouTube feeds are collected even when the main machine is sleeping/rebooting
3. **Resource offload** — Playwright/Chromium for headless scraping uses significant RAM; offloading to themistocles frees main machine resources
4. **Unified data store** — SQLite DB lives on themistocles; frontend accesses it over LAN HTTP
5. **LLM-independent core pipeline** — Heuristic classification works without any LLM; when LLM is needed later, point to main machine's server

---

### Scenario B: "Workspace Backup & Data Mirror"

**What runs on themistocles:**
- `rsync` or `syncthing` for periodic workspace sync
- Optional: `git` for mirroring the workspace repo

**What stays on the main system:**
- Everything — themistocles is a passive mirror

**How they communicate:**
```
Main Machine                               Themistocles (192.168.0.122)
┌─────────────────────────┐    rsync/SSH   ┌──────────────────────────────┐
│  /home/anupam/Desktop/  │───────────────▶│  /home/anupam/backup/        │
│  workspace/             │   (hourly)     │  workspace/                  │
│                         │                │                              │
│  /home/anupam/llama-cpp/│───────────────▶│  /home/anupam/backup/        │
│  (llama.cpp binaries)   │   (weekly)     │  llama-cpp/                  │
│                         │                │                              │
│  LLM models (16 GB)     │───────────────▶│  /home/anupam/backup/        │
│  /llm/gemma/            │   (weekly)     │  models/                     │
└─────────────────────────┘                └──────────────────────────────┘
                                   454 GB SSD, 426 GB free
```

**Value provided:**
1. **Off-site resilience** — 426 GB of free space can hold full workspace + models + historical snapshots
2. **Data safety** — Survival infra's JSONL data, feed analyser's SQLite DB, and LLM models are all backed up off the main machine
3. **Quick restore** — If main machine storage fails, data is immediately accessible over LAN
4. **Versioned snapshots** — `rsync --link-dest` can maintain daily/weekly snapshots without duplicating unchanged files
5. **Zero runtime dependency** — Only needs `rsync` and SSH, both already working

---

### Scenario C: "Survival Infra Secondary Instance + Remote LLM"

**What runs on themistocles:**
- Survival infra Flask app (bare-metal, `python app.py`)
- SSH tunnel to main machine's LLM server

**What stays on the main system:**
- LLM inference server (port 8012)
- Primary survival infra instances
- Feed analyser

**How they communicate:**
```
Main Machine                               Themistocles (192.168.0.122)
┌─────────────────────────┐    SSH tunnel  ┌──────────────────────────────┐
│  LLM Inference Server   │◀━━━━━━━━━━━━━━│  Survival Infra (Flask)      │
│  (:8012)                │   localhost    │  (:5051)                     │
│                         │   :18012 ──▶   │  LLM_BASE_URL=              │
│                         │   remote       │  http://127.0.0.1:18012     │
│                         │   :8012        │                              │
│  Primary Survival Infra │                │  Data: ./data-themistocles/   │
│  (:5151/5152/5153)      │                │  ├─ raw_captures.jsonl       │
│                         │                │  ├─ events/                  │
│                         │                │  ├─ wiki/                    │
│                         │                │  └─ people/                  │
└─────────────────────────┘                └──────────────────────────────┘
```

**SSH tunnel command (on themistocles):**
```bash
ssh -N -L 18012:127.0.0.1:8012 anupam@<main-machine-ip> &
```

**Value provided:**
1. **Dedicated capture endpoint** — Always-on event capture, independent of main machine state
2. **Separate data domain** — Different `SURVIVAL_DATA_DIR` for different use contexts (e.g., work vs. personal events)
3. **Capture survives main machine downtime** — Events can be captured while main machine is off; extraction queues up and processes when LLM becomes reachable again
4. **Network resilience** — If SSH tunnel drops, capture-only mode still works; extraction resumes on reconnect

**Risk:** Extraction/wiki synthesis latency increases. If main machine is off, all LLM operations fail (but capture continues). The SSH tunnel is a single point of failure — use `autossh` for automatic reconnection.

---

## Section 3: Implementation Roadmap (Scenario A — Top Recommendation)

### 3.1 Prerequisites: Install on Themistocles

SSH into themistocles and run:

```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install Python essentials (3.13 already present)
sudo apt install -y python3-pip python3-venv git curl

# 3. Install Node.js (for frontend — optional, can skip if frontend stays on main)
# sudo apt install -y nodejs npm

# 4. Install Playwright dependencies for headless scraping
sudo apt install -y \
    libnss3 libnspr4 libatk-bridge2.0-0 libdrm2 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
    libasound2 libpango-1.0-0 libcairo2 libatspi2.0-0
```

### 3.2 Clone and Setup Feed Analyser Backend

```bash
# 5. Create workspace directory
mkdir -p ~/workspace && cd ~/workspace

# 6. Clone or rsync the feed_analyser from main machine
# Option A: rsync from main (recommended)
rsync -avz --exclude='.venv' --exclude='node_modules' \
    --exclude='__pycache__' --exclude='.git' \
    anupam@<main-machine-ip>:/home/anupam/Desktop/workspace/feed_analyser/ \
    ~/workspace/feed_analyser/

# Option B: git clone (if repo is accessible)
# git clone <repo-url> feed_analyser

# 7. Set up Python virtual environment
cd ~/workspace/feed_analyser
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt

# 8. Install Playwright browser
playwright install chromium

# 9. Create data directories
mkdir -p backend/raw_data
```

### 3.3 Configuration Changes

**On themistocles** — no changes needed to backend code. The heuristic fallback works automatically when Ollama is unreachable.

**Optional: Point classifier to main machine's LLM for better quality:**
```bash
# Edit backend/classifier.py and change:
# OLLAMA_URL = "http://<main-machine-ip>:11434/api/generate"
```

Or better, point it to the workspace LLM server (if it exposes an Ollama-compatible endpoint, or add an OpenAI-compatible classifier path).

**On the main machine** — update the frontend to point to themistocles:
```bash
# In feed_analyser/frontend/vite.config.js, update the proxy target:
# target: 'http://192.168.0.122:8000'
```

### 3.4 Start Services on Themistocles

```bash
# 10. Start the backend API
cd ~/workspace/feed_analyser
source .venv/bin/activate
cd backend
uvicorn main:app --host 0.0.0.0 --port 8000 &

# 11. Start the directory watcher (in a separate terminal or tmux/screen)
python directory_watcher.py &

# 12. Verify backend is up
curl http://192.168.0.122:8000/api/ideas?limit=1
```

### 3.5 Set Up Cron Jobs for Automated Ingestion

```bash
# 13. Add to crontab (crontab -e)

# Twitter scraping — every 4 hours
0 */4 * * * cd ~/workspace/feed_analyser && .venv/bin/python scripts/twitter_headless.py >> ~/logs/twitter_scrape.log 2>&1

# YouTube scraping — daily at 2 AM
0 2 * * * cd ~/workspace/feed_analyser && bash scripts/youtube_cron.sh >> ~/logs/youtube_scrape.log 2>&1

# 14. Create log directory
mkdir -p ~/logs
```

### 3.6 Optional: Systemd Services for Persistence

Instead of background processes, create systemd units for resilience:

```bash
# /etc/systemd/system/feed-analyser-api.service
sudo tee /etc/systemd/system/feed-analyser-api.service << 'EOF'
[Unit]
Description=Feed Analyser Backend API
After=network.target

[Service]
Type=simple
User=anupam
WorkingDirectory=/home/anupam/workspace/feed_analyser/backend
Environment="PATH=/home/anupam/workspace/feed_analyser/.venv/bin:/usr/bin"
ExecStart=/home/anupam/workspace/feed_analyser/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable feed-analyser-api
sudo systemctl start feed-analyser-api
```

### 3.7 Firewall (if needed)

```bash
# Allow backend API on LAN
sudo ufw allow from 192.168.0.0/24 to any port 8000 proto tcp
```

### 3.8 Estimated Resource Usage After Deployment

| Component | RAM | CPU (idle) | Disk |
|---|---|---|---|
| FastAPI backend | ~150 MB | ~1% | ~2 MB (code) |
| Directory watcher | ~30 MB | ~0.5% | — |
| SQLite data.db | — | — | ~10–100 MB (grows) |
| Playwright (when scraping) | ~300 MB | ~30% (burst) | — |
| Chromium browser | — | — | ~300 MB (installed) |
| **Total (idle)** | **~200 MB** | **~1.5%** | **~15 GB max** |
| **Total (scraping)** | **~500 MB** | **~30%** | — |

Themisto has 3.2 GB free — this uses at most 500 MB, leaving 2.7 GB for system and future use.

---

## Appendix: Quick-Reference Commands

### Test connectivity
```bash
ssh anupam@192.168.0.122 "hostname && whoami && pwd"
```

### Check system resources
```bash
ssh anupam@192.168.0.122 "free -h && df -h / && uptime"
```

### Sync workspace data (one-shot)
```bash
rsync -avz --exclude='.venv' --exclude='node_modules' --exclude='__pycache__' \
    --exclude='.git' --exclude='gemma/' \
    /home/anupam/Desktop/workspace/ \
    anupam@192.168.0.122:~/backup/workspace/
```

### Start SSH tunnel for LLM (Scenario C)
```bash
# On themistocles:
ssh -N -L 18012:127.0.0.1:8012 anupam@<main-machine-ip> &
# Then set on themistocles:
# export SURVIVAL_LLM_BASE_URL=http://127.0.0.1:18012
```

### Persistent SSH tunnel with autossh
```bash
# Install: sudo apt install autossh
autossh -M 0 -N -L 18012:127.0.0.1:8012 anupam@<main-machine-ip> &
```

---

## Summary

Themistocles is best used as an **ingestion automation and data node**, not as a compute server. Its 3.7 GB RAM makes LLM inference impossible, but its 454 GB SSD, always-on Wi-Fi connectivity, and Python 3.13 make it ideal for:

1. ⭐ **Feed analyser backend + ingestion cron** — offload scraping and classification
2. **Workspace data backup** — 426 GB of free space for rsync mirrors
3. **Survival infra secondary instance** — always-on event capture with remote LLM tunnel

Start with Scenario A (ingestion node). It delivers immediate value with the least setup and no Docker dependency.
