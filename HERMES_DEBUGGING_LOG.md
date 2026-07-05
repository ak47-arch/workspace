# Hermes Debugging Log

## Date: 2026-07-05
## Issue: Hermes Agent (deepseek-v4-flash via OpenRouter) fails to use tools — responds with "bash\nls -la" as text instead of structured `tool_calls`

---

## Root Cause: `disabled_toolsets` contained `coding`

**File:** `~/.hermes/config.yaml`

```yaml
# BEFORE (broken)
disabled_toolsets:
    - coding           # ← THIS WAS THE BUG
    - computer_use
    - discord
    ...

# AFTER (fixed)
disabled_toolsets:
    - computer_use
    - discord
    ...
```

The `coding` toolset is a composite toolset that resolves to **every core tool**:
`browser_back, browser_cdp, browser_click, browser_console, browser_dialog,
browser_get_images, browser_navigate, browser_press, browser_scroll,
browser_snapshot, browser_type, browser_vision, clarify, close_terminal,
delegate_task, execute_code, memory, patch, process, read_file, read_terminal,
search_files, session_search, skill_manage, skill_view, skills_list, terminal,
todo, vision_analyze, web_extract, web_search, write_file`

When `coding` was in `disabled_toolsets`, the subtraction logic in
`model_tools.get_tool_definitions()` removed ALL of these tools from the
enabled set — leaving **0 tools** loaded. Without tool definitions, the
model never received `tool_choice: "auto"` and never generated structured
tool calls. It fell back to writing text like `"bash\nls -la"`.

---

## Secondary Fix: `api_kwargs["tool_choice"] = "auto"`

**File:** `agent/transports/chat_completions.py`

The `chat_completions` transport did not set `tool_choice` when tools were
provided. The `codex_responses` transport (Responses API) already had
`tool_choice: "auto"`, but `chat_completions` did not.

Without explicit `tool_choice: "auto"`, OpenRouter defaults the model to
text-only mode even when tool definitions are present.

**Added in two code paths** (legacy and provider-profile):

```python
api_kwargs["tools"] = tools
api_kwargs["tool_choice"] = "auto"    # ← added
```

Lines 320 and 505 in the fork (`~/Desktop/workspace/hermes/agent/transports/chat_completions.py`).

---

## Tertiary Fix: `Bash` → `terminal` alias in repair function

**File:** `agent/agent_runtime_helpers.py`

Some models (like deepseek-v4-flash) are trained to emit `Bash` as the
shell execution tool name instead of `terminal`. The `_repair_tool_call`
function normalizes tool names (lowercase, CamelCase, strip `_tool` suffix,
fuzzy match) but `bash` → `terminal` has too low a similarity score for
fuzzy matching (0.7 cutoff).

Added a manual alias map at the start of `repair_tool_call()`:

```python
_TOOL_NAME_ALIASES = {
    "bash": "terminal",
}
alias_target = _TOOL_NAME_ALIASES.get(tool_name.lower())
if alias_target and alias_target in agent.valid_tool_names:
    return alias_target
```

This is a safety net — the primary fix (`tool_choice` + correct
`disabled_toolsets`) ensures tools are sent to the model with the right
names, so this alias only triggers if the model hallucinates despite
correct tool definitions.

---

## Additional Issue: Docker volume mount for workspace access

**File:** `~/.hermes/config.yaml`

The Docker container sandbox didn't have access to the host filesystem
where the resume project lives. Added a volume mount:

```yaml
docker_volumes:
    - /home/anupam/Desktop/workspace/resume:/workspace/resume
```

When changing this, old Docker containers must be killed (`docker rm -f`)
so Hermes spawns a new container with the mount. Verify with:

```bash
docker inspect <container-id> --format '{{json .Mounts}}' | python3 -m json.tool
```

---

## Install Locations

There are two copies of the codebase:

| Location | Installed via | Status |
|----------|--------------|--------|
| `~/.hermes/hermes-agent/` | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash` | **Active install** (has all fixes) |
| `~/Desktop/workspace/hermes/` | Local fork / source clone | **Source fork** (patches ready — see below) |

### Fixes applied to the fork (`~/Desktop/workspace/hermes/`)

These are ready for when you install from the fork:

| Fix | File | Change | git diff |
|-----|------|--------|----------|
| `tool_choice: "auto"` | `agent/transports/chat_completions.py` | Added `api_kwargs["tool_choice"] = "auto"` after `api_kwargs["tools"] = tools` on both code paths (lines 320, 505) | +2 |
| `Bash` → `terminal` alias | `agent/agent_runtime_helpers.py` | Added `_TOOL_NAME_ALIASES` dict at start of `repair_tool_call()` | +10 |
| Remove `coding` from disabled | `~/.hermes/config.yaml` *(not in source)* | Set at install time during `hermes setup` | N/A |

Verify the fixes are applied:

```bash
grep -n "tool_choice" ~/Desktop/workspace/hermes/agent/transports/chat_completions.py
# Expected output:
# 320:            api_kwargs["tool_choice"] = "auto"
# 505:            api_kwargs["tool_choice"] = "auto"

grep -A4 "TOOL_NAME_ALIASES" ~/Desktop/workspace/hermes/agent/agent_runtime_helpers.py
# Expected output:
#     _TOOL_NAME_ALIASES = {
#         "bash": "terminal",
#     }
```

---

## How we diagnosed it

### Step 1: Observed the symptom
The model output `"bash\nls -la"` as plain text in the response box.
No tool preparation indicators (`┊ ⚡ preparing terminal…`) appeared.

### Step 2: Checked the agent log
`~/.hermes/logs/agent.log` showed:
```
Turn ended: reason=text_response(finish_reason=stop) tool_turns=0
```
Every API call returned `finish_reason=stop` with no `tool_calls`.

### Step 3: Direct API test proved the model works
```bash
curl -s "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -d '{"model":"deepseek/deepseek-v4-flash",
       "messages":[{"role":"user","content":"run: ls -la"}],
       "tools":[{...}],
       "tool_choice":"auto"}'
```
Response: `finish_reason: tool_calls` with `terminal` tool.
**Conclusion:** Model + API support tool calling fine.

### Step 4: Added debug logging to trace the code path
Added WARNING-level logs to:
- `agent/transports/chat_completions.py` — verify `tool_choice` is set
- `agent/agent_init.py` — verify tools are loaded

### Step 5: Found `tools=None` at the transport
```
CHAT_COMPLETIONS: using PROFILE path tools=None
CHAT_PROFILE_ENTER: tools=list len=0
```

### Step 6: Found `tools_loaded=0`
```
AGENT_INIT: tools_loaded=0 enabled=[...] disabled=[...]
```
The tools were empty at agent initialization time.

### Step 7: Isolated the culprit — `disabled_toolsets` subtraction
Tested each disabled toolset individually:
```python
Disabled coding: 0 tools    ◄── CAUSED THE BUG
Disabled computer_use: 24 tools
Disabled discord: 24 tools
...
```
The `coding` toolset resolved to nearly ALL core tools. Its subtraction
emptied the entire tool list.

### Step 8: Removed `coding` from `disabled_toolsets`
```yaml
AGENT_INIT: tools_loaded=24 enabled=[...] disabled=[...]
CHAT_PROFILE: tools=24 tool_choice=auto
```
The model immediately generated proper `tool_calls` with `terminal`.

---

## Timeline

| Time | Event |
|------|-------|
| 20:51 | Started investigating broken hermes session |
| 21:05 | Changed `api_mode: codex_responses` → `chat_completions` in old config |
| 21:15 | Uninstalled old install, fresh install from official source |
| 21:50 | Added `Bash → terminal` alias in `agent_runtime_helpers.py` |
| 22:20 | Added `tool_choice: "auto"` to `chat_completions.py` |
| 22:50 | Cleared `__pycache__` multiple times |
| 23:56 | Added extensive debug logging to trace empty tools |
| 00:18 | **Found `coding` in `disabled_toolsets` causing 0 tools** |
| 00:25 | Fixed config → tools loaded = 24, tool calls working |
| 00:45 | Added Docker volume mount for workspace access |
| 01:00 | Applied all fixes to the fork (`~/Desktop/workspace/hermes/`) |

---

## Files Modified

### Active install (`~/.hermes/hermes-agent/`)
| File | Change | Critical? |
|------|--------|-----------|
| `~/.hermes/config.yaml` | Removed `coding` from `disabled_toolsets` | **Yes — root cause** |
| `~/.hermes/config.yaml` | Added `docker_volumes` mount for resume workspace | Yes |
| `agent/transports/chat_completions.py` | Added `tool_choice: "auto"` | Yes — safety net |

### Fork (`~/Desktop/workspace/hermes/`)
| File | Change | Critical? |
|------|--------|-----------|
| `agent/transports/chat_completions.py` | Added `tool_choice: "auto"` (lines 320, 505) | **Yes** |
| `agent/agent_runtime_helpers.py` | Added `Bash → terminal` alias in `repair_tool_call()` | Nice-to-have |

### Config (apply after fork install)
| File | Change | Critical? |
|------|--------|-----------|
| `~/.hermes/config.yaml` | Remove `coding` from `disabled_toolsets` | **Yes** |
| `~/.hermes/config.yaml` | Add `docker_volumes` if using Docker backend | As needed |

---

## What to check next time tools aren't working

1. **Check the agent log** — Look for `tool_turns=0` and `finish_reason=stop`
2. **Direct API test** — curl OpenRouter with `tool_choice: "auto"` to verify the model supports tool calling
3. **Check `tools_loaded`** — Add a log at `agent_init.py` line 1065 to see the tool count
4. **Check `disabled_toolsets`** — Verify no composite toolset (like `coding`) is in the disabled list
5. **Check `tool_choice`** — Verify `api_kwargs["tool_choice"] = "auto"` is set in the transport
6. **Check the system prompt** — Ensure it tells the model which tools to use and how to call them