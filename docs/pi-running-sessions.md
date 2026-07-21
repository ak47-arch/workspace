# Pi Agent Running Sessions — With Session IDs

Generated: Mon Jul 20 20:23 (2026)

---

## Pi Agent Sessions (9 total)

### PID 2265718 — ⬤ CURRENT (this session)
| Field | Value |
|-------|-------|
| **Status** | Sl+ (active) |
| **RSS** | ~302 MB |
| **Started** | Mon Jul 20 20:18:34 |
| **TTY** | pts/5 |
| **Parent** | /bin/bash |
| **Session ID** | `019f8000-15a5-726a-bc5c-bd341243b148` |
| **Session file** | `2026-07-20T14-48-37-029Z_019f8000-15a5-726a-bc5c-bd341243b148.jsonl` (161K) |
| **Model** | deepseek/deepseek-v4-flash |

---

### PID 290820 — Idle
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~113 MB |
| **Started** | Sun Jul 19 22:06:41 (~22 hrs ago) |
| **TTY** | pts/3 |
| **Parent** | /bin/bash |
| **Likely session** | `019f79c2-3f42-7370-917e-01d832a64b82` (1.1M, modified Jul 20 00:01) |
| | Started Jul 19 09:43, had ~1MB of conversation |

---

### PID 3773883 — Idle
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~79 MB |
| **Started** | Sun Jul 19 15:15:34 (~29 hrs ago) |
| **TTY** | pts/7 |
| **Parent** | /bin/bash |
| **Likely sessions** | `019f79a7-602a-798d-9d33-87a1f494d32d` (161K) |
| | `019f79c2-f10d-747e-a1d2-562f168c2220` (163K) |

---

### PID 1661330 — Idle
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~175 MB |
| **Started** | Mon Jul 20 14:12:26 (~6 hrs ago) |
| **TTY** | pts/10 |
| **Parent** | /bin/bash |
| **Likely session** | `019f649f-47df-7d12-a525-6285733e3d6e` (3.1M, modified Jul 20 15:43) |
| | Started Jul 15 07:13, big session |

---

### PID 2207833 — Stale (5 days)
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~216 MB |
| **Started** | Wed Jul 15 12:43:22 |
| **TTY** | pts/6 |
| **Parent** | /bin/bash |
| **Likely sessions** | `019f60c4-d401-793a-97c1-1c89363ab0e4` (324K) |
| | `019f6456-aba8-72a9-9c5b-bb2f71a4129b` (174K) |

---

### PID 1535904 — Stale (7 days)
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~117 MB |
| **Started** | Mon Jul 13 10:54:12 |
| **TTY** | pts/4 |
| **Parent** | /bin/bash |
| **Likely session** | `019f55cf-1354-78c4-ab41-73007dcafc40` (1.1M, modified Jul 13 12:26) |

---

### PID 1182736 — Stale (9 days)
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~96 MB |
| **Started** | Sat Jul 11 20:34:08 |
| **TTY** | pts/8 |
| **Parent** | /bin/bash |
| **Likely session** | `019f427d-8556-7dc8-8bc2-e8c156992f27` (652K, modified Jul 11 22:32) |

---

### PID 1182749 — Stale (9 days)
| Field | Value |
|-------|-------|
| **Status** | Sl+ (idle) |
| **RSS** | ~98 MB |
| **Started** | Sat Jul 11 20:34:08 |
| **TTY** | pts/9 |
| **Parent** | /bin/bash |

---

### PID 1183622 — Stopped/Suspended
| Field | Value |
|-------|-------|
| **Status** | **Tl** (stopped/traced) |
| **RSS** | ~0 MB |
| **Started** | Sat Jul 11 20:34:43 |
| **TTY** | pts/4 |
| **Parent** | /bin/bash |

---

## Summary Table

| PID | TTY | RAM | Age | Session ID | Status |
|-----|-----|-----|-----|------------|--------|
| **2265718** | pts/5 | 302 MB | **now** | **`019f8000-15a5-726a-bc5c-bd341243b148`** | **⬤ ACTIVE** |
| 290820 | pts/3 | 113 MB | 22 hrs | `019f79c2-3f42-7370-917e-01d832a64b82` | Idle |
| 3773883 | pts/7 | 79 MB | 29 hrs | `019f79a7-602a-798d-9d33-87a1f494d32d` | Idle |
| 1661330 | pts/10 | 175 MB | 6 hrs | `019f649f-47df-7d12-a525-6285733e3d6e` | Idle |
| 2207833 | pts/6 | 216 MB | **5 days** | `019f60c4-d401-793a-97c1-1c89363ab0e4` | Stale |
| 1535904 | pts/4 | 117 MB | **7 days** | `019f55cf-1354-78c4-ab41-73007dcafc40` | Stale |
| 1182736 | pts/8 | 96 MB | **9 days** | `019f427d-8556-7dc8-8bc2-e8c156992f27` | Stale |
| 1182749 | pts/9 | 98 MB | **9 days** | ? | Stale |
| 1183622 | pts/4 | ~0 MB | **9 days** | ? | **Stopped** |

**Total RAM from idle/stopped sessions: ~894 MB**

---

## How to resume a session

```bash
# Resume by session ID (from terminal)
pi --resume-session 019f79c2-3f42-7370-917e-01d832a64b82

# Or open the session file directly
pi --session /home/anupam/.pi/agent/sessions/--home-anupam-Desktop-workspace--/2026-07-19T09-43-21-154Z_019f79c2-3f42-7370-917e-01d832a64b82.jsonl
```

## Quick kill command

```bash
kill 290820 1182736 1182749 1183622 1535904 1661330 2207833 3773883
```
