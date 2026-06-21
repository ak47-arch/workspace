# Headroom ↔ Pi Integration Plan

**Goal:** Route all pi coding-agent traffic through Headroom's compression proxy so
every session gets 60–92% token reduction automatically, with crash recovery and
liveness monitoring to protect against unbilled token spend.

**Date:** 2026-06-20
**Status:** ✅ Planning — ❌ Pending — ⬜ In Progress — ✅ Done

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  User runs:  pi  (via headroom-pi wrapper)               │
│                     │                                    │
│                     ▼                                    │
│  ┌─────────────────────────────────────┐                │
│  │  headroom-pi.sh                     │                │
│  │  ───────────────────────────────    │                │
│  │  Checks systemctl is-active →       │                │
│  │  if inactive → systemctl start      │                │
│  │  then exec pi "$@"                  │                │
│  └────────────┬────────────────────────┘                │
│               │                                         │
│               │  ┌──────────────────────────────┐       │
│               │  │ systemd: headroom-proxy      │       │
│               ├──│  • Type=simple               │       │
│               │  │  • Restart=on-failure        │       │
│               │  │  • RestartSec=2              │       │
│               │  │  • Runs headroom proxy :8787 │       │
│               │  └──────────────────────────────┘       │
│               │                                          │
│               │  ┌──────────────────────────────┐       │
│               │  │ systemd: headroom-health.timer│       │
│               │  │  • Every 60s: curl /livez    │       │
│               │  │  • On failure: log + alert   │       │
│               │  └──────────────────────────────┘       │
│               │                                          │
│               ▼                                          │
│  ┌─────────────────────────────────────┐                │
│  │  pi (coding agent)                  │                │
│  │  ───────────────────────────────    │                │
│  │  routes through custom provider     │                │
│  │  → http://localhost:8787/v1         │                │
│  └────────────┬────────────────────────┘                │
│               │                                         │
│               ▼                                         │
│  ┌─────────────────────────────────────┐                │
│  │  Headroom Proxy (:8787)             │                │
│  │  ───────────────────────────────    │                │
│  │  • SmartCrusher (JSON)              │                │
│  │  • CodeCompressor (AST)             │                │
│  │  • CacheAligner                     │                │
│  │  • CCR (reversible cache)           │                │
│  │  • Memory / Learning                │                │
│  └────────────┬────────────────────────┘                │
│               │                                         │
│               ▼                                         │
│  ┌─────────────────────────────────────┐                │
│  │  Upstream LLM (Anthropic / ...)     │                │
│  └─────────────────────────────────────┘                │
└──────────────────────────────────────────────────────────┘
```

---

## Files to create

| # | File | Purpose | Status |
|---|------|---------|--------|
| 1 | `~/.config/systemd/user/headroom-proxy.service` | Systemd user unit managing the Headroom proxy process | ✅ Done |
| 2 | `~/.local/bin/headroom-health-check` | Script that checks `/livez` and alerts on failure | ✅ Done |
| 3 | `~/.config/systemd/user/headroom-health-check.service` | Systemd service wrapper for the health check | ✅ Done |
| 4 | `~/.config/systemd/user/headroom-health-check.timer` | Timer that runs health check every 60s | ✅ Done |
| 5 | `~/.local/bin/headroom-pi` | Shell wrapper that ensures proxy is running before `pi` | ✅ Done |
| 6 | `~/.pi/agent/models.json` | Custom provider config pointing pi at Headroom | ✅ Done |
| 7 | `~/.bashrc` alias | `alias pi=headroom-pi` to transparently wrap pi | ✅ Done |

---

## Implementation steps

### Step 1: Systemd service — `headroom-proxy.service`

**What:** A `Type=simple` **user-level** unit at `~/.config/systemd/user/headroom-proxy.service` that runs `headroom proxy --port 8787` with:
- `Restart=on-failure` (auto-restart on crash within ~2s)
- `RestartSec=2` (small delay before restart to avoid tight loops)
- Log to journald (viewable via `journalctl --user -u headroom-proxy`)
- Runs as the current user (no sudo needed)
- `loginctl enable-linger` ensures it starts after reboot

**Success criteria:** `systemctl --user start headroom-proxy` → `systemctl --user is-active` → `active` → `curl /livez` returns `{"alive":true}`

### Step 2: Health-check script — `headroom-health-check`

**What:** A bash script at `~/.local/bin/headroom-health-check` that:
1. `curl -sf http://127.0.0.1:8787/livez`
2. On failure: writes to syslog (`logger`), desktop notification (`notify-send`), optionally Slack webhook via `$HEADROOM_SLACK_WEBHOOK`
3. Exits with 0 on success, 1 on failure (so systemd timer can track it)

**Success criteria:** `headroom-health-check` exits 0 when proxy is running, exits 1 when proxy is down (verified)

### Step 3: Health-check systemd timer

**What:** Two files in `~/.config/systemd/user/`:
- `headroom-health-check.service` — runs the health-check script
- `headroom-health-check.timer` — triggers the service every 60 seconds

**Why separate timer + service:** This is the standard systemd pattern. The timer fires, `OnFailure=` alerts can be set on the service, and the service has a clean audit trail in journald.

**Success criteria:** `systemctl --user list-timers` shows `headroom-health-check.timer` with last-triggered time (verified)

### Step 4: Auto-start on boot

**What:** `systemctl enable headroom-proxy` and `systemctl enable headroom-health-check.timer`
so both survive reboots.

**Success criteria:** After reboot, proxy is running and health checks are active without manual intervention.

### Step 5: Shell wrapper — `headroom-pi.sh`

**What:** A bash script at `~/.local/bin/headroom-pi` that wraps `pi`:
1. Check `systemctl --user is-active headroom-proxy`
2. If inactive → `systemctl --user start headroom-proxy`
3. Wait up to ~10s polling `/livez` until proxy comes up
4. On timeout: print error message — continues without compression
5. `exec pi "$@"` (replaces shell process with pi)

**Modes:**
- `headroom-pi` — normal flow above
- `headroom-pi --status` — print proxy status + version + uptime
- `headroom-pi --restart` — `systemctl --user restart headroom-proxy` then pi
- `headroom-pi --no-proxy` — skip proxy check, directly exec pi
- `headroom-pi --stop` — stop the proxy service

**Success criteria:** Verified: `headroom-pi --status` shows active proxy, `headroom-pi --version` passes through to pi correctly

### Step 6: Pi provider config — `models.json`

**What:** Register Headroom as a custom provider in pi:

```json
{
  "providers": {
    "headroom": {
      "baseUrl": "http://localhost:8787/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "models": [
        {
          "id": "anthropic/claude-sonnet-4-20250514",
          "name": "Sonnet 4 (via Headroom)",
          "reasoning": true,
          "input": ["text", "image"],
          "contextWindow": 200000,
          "maxTokens": 8192,
          "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 3.75 }
        },
        {
          "id": "anthropic/claude-opus-4-20250514",
          "name": "Opus 4 (via Headroom)",
          "reasoning": true,
          "input": ["text", "image"],
          "contextWindow": 200000,
          "maxTokens": 8192,
          "cost": { "input": 15, "output": 75, "cacheRead": 1.5, "cacheWrite": 18.75 }
        }
      ]
    }
  }
}
```

**Note:** This must also be compatible with Headroom's backend routing. Headroom's proxy might expect a specific `model` ID that matches what the upstream provider knows. The model IDs in `models.json` are what pi sends — Headroom should pass them through to the upstream. This may need adjustment when we test.

### Step 7: Shell alias

**What:** Add to `~/.zshrc`:
```bash
alias pi=/home/anupam/Desktop/workspace/headroom-pi.sh
```

**Success criteria:** Typing `pi` in a new terminal invokes the wrapper.

---

## Error/edge case matrix

| Situation | Behavior |
|---|---|
| Proxy crashes | systemd `Restart=on-failure` brings it back in ~2s. If it crash-loops (restarts >5 times in 10s), systemd backs off to 1min between restarts. |
| Proxy hangs (alive but not serving) | Health-check timer catches it within ~60s. Logs + alert. No auto-restart on hang (conservative — a manual investigation is better than a blind force-restart that drops in-flight requests). |
| First run (no credentials configured) | Headroom will fail to forward requests but still serves `/livez`. Health-check passes. pi will get 401s from upstream → user sees auth errors rather than compression. Acceptable — credentials are a setup prerequisite. |
| Machine reboot | Both services are `enabled` → start automatically. No manual steps. |
| Port 8787 taken by another process | `headroom proxy` exits immediately. systemd `Restart=on-failure` loops. Health-check timer fails. User checks `journalctl -u headroom-proxy` and resolves conflict. |
| User updates Headroom | `systemctl restart headroom-proxy` picks up the new version. |
| User uninstalls Headroom | `headroom proxy` binary is gone → systemd `ExecStart` fails → `Restart=on-failure` loops → health-check alerts. User disables the service. |
| User wants to bypass compression | `headroom-pi --no-proxy` → skips check, `exec pi` directly. |

---

## Testing plan

| Test | Method | Expected | Actual |
|------|--------|----------|--------|
| Proxy starts | `systemctl --user start headroom-proxy` | `active (running)` | ✅ `active` |
| `/livez` responds | `curl localhost:8787/livez` | JSON with `"alive": true` | ✅ Returns version + uptime |
| Health check passes | `headroom-health-check` | Exit 0 | ✅ Exit 0 |
| Health check fails | Stop proxy, run check | Exit 1 | ✅ Exit 1 |
| Crash recovery | `kill $(systemctl --user show -p MainPID headroom-proxy)` | Restarts within ~2s | ⬜ Not yet tested |
| Boot persistence | `systemctl --user enable` + reboot | Service active | ⬜ Requires reboot |
| Wrapper launches pi | `headroom-pi --version` | pi version output | ✅ `0.79.8` |
| Wrapper status | `headroom-pi --status` | `Proxy: running` | ✅ Shows version + uptime |
| Wrapper bypass | `headroom-pi --no-proxy --version` | pi version output | ✅ `0.79.8` |
| pi models config | Parse `~/.pi/agent/models.json` | Valid JSON, 4 models | ✅ Valid, 4 models |
| Shell alias | `grep 'alias pi=' ~/.bashrc` | Alias present | ✅ Added |

---

## Future enhancements (v2)

- Native sd_notify support: PR to Headroom to call `sd_notify("WATCHDOG=1")` from the lifespan loop, enabling `Type=notify` + instant hang detection
- Headroom dashboard integration: embed Headroom's stats/metrics in pi's footer or status bar
- Auto-calc model costs: script that reads Headroom's dashboard API to compute real token savings
- Multi-user alerting channel: Slack/Discord webhook on health-check failure for team-wide visibility

---

## Actual implementation

### Deviations from original plan

| Original | Actual | Reason |
|----------|--------|--------|
| `/etc/systemd/system/` (system-level) | `~/.config/systemd/user/` (user-level) | No sudo access. User services have same capabilities (`Restart=on-failure`, timers, linger for boot persistence). |
| `/usr/local/bin/` scripts | `~/.local/bin/` scripts | Same reason — user-level install. `~/.local/bin` is already on `$PATH`. |
| `/home/anupam/Desktop/workspace/headroom-pi.sh` | `~/.local/bin/headroom-pi` | Placed directly on PATH instead of adding a second symlink. |
| Manage via `systemctl` | Manage via `systemctl --user` | User service convention — no functional difference. |

### Bonus additions

- Created `~/.local/bin/headroom` → symlink to the headroom binary for easy CLI access
- Installed `[proxy]` extras (FastAPI, Uvicorn, MCP, transformers, ONNX Runtime) — these are required for the proxy to run

### Remaining manual action

- User needs to run `systemctl --user enable headroom-proxy.service` and log out/in (or `source ~/.bashrc`) for the `pi` alias to take effect
- User needs to select `headroom/claude-sonnet-4-20250514` in pi via `/model` to start routing through compression
