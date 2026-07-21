2026-07-21

## Browser Automation Tools: agent-browser vs web-search Skill — Full Comparison & Decision

We evaluated two browser automation approaches for the pi coding agent environment. After installing, testing, and understanding both, we decided to use the **web-search skill** instead of the **agent-browser + pi-agent-browser-native extension** due to resource constraints.

### The Two Systems

**agent-browser + pi-agent-browser-native extension (uninstalled):**
- `agent-browser` is a **Rust CLI** from Vercel Labs that manages its own Chrome for Testing binary
- `pi-agent-browser-native` is a **pi extension** that wraps `agent-browser` as a native `agent_browser` tool
- Architecture: Rust daemon (~26 MB) + Chrome for Testing (headless, CDP-based, ~200-400 MB per session)
- Supports multiple isolated sessions, each with its own browser instance
- Full browser automation (click, fill, snapshot, eval, scroll, keyboard, etc.)
- Session persistence, profiles, state save/restore, MCP server, dashboard
- Has `agent_browser_web_search` companion tool requiring Brave or Exa API keys (paid)
- The extension injects prompt guidelines steering agents away from search engine forms and toward the paid API tool
- Comes with a bash guard that intercepts `agent-browser` bash commands and redirects to the native tool

**web-search skill (currently active):**
- A **Node.js CLI** using Playwright, bundled as a pi skill (from ogulcancelik/agent-skills)
- Architecture: Node.js HTTP daemon on port 9377 (~40-60 MB) + Chromium browser (~200-400 MB)
- Single session per daemon (no multi-session isolation)
- Focused on search + extraction: built-in Google/DuckDuckGo search, bot protection, markdown extraction
- Auto-recycles browser after 4 hours or 75 requests to manage memory
- Can adopt an existing CDP-enabled browser instead of launching its own
- Built-in bot protection (Cloudflare, Anubis PoW, Google consent pages) and browser fingerprinting
- **Free** — no API keys needed (uses a real browser to search)

### Detailed Architecture Comparison

| Aspect | agent-browser | web-search skill |
|---|---|---|
| Language | Rust (daemon + CLI) | Node.js (Playwright) |
| Browser engine | Chrome for Testing (auto-downloaded) | Any Chromium-family browser (auto-detected) |
| Automation protocol | CDP via Rust CDP bindings | CDP via Playwright's `connectOverCDP` |
| Daemon model | Long-lived Rust daemon, multi-session | Long-lived Node.js HTTP server, single session |
| Browser launch | `--remote-debugging-port=0` (ephemeral) | `--ozone-platform=headless` (Linux) or `--headless=new` |
| Profile | Temp dir per session (`/tmp/agent-browser-chrome-<uuid>`) | Configurable (`~/.config/web-search-cdp-profile-chrome`) |
| Existing browser adoption | N/A — always launches fresh | Tries ports 9225/9222 before launching its own |
| Search approach | Manual navigation to search engines | Built-in Google first, DuckDuckGo fallback |
| Content extraction | Manual (get text, eval, read) | Automatic via Playwright + Readability + Turndown |
| Idle timeout | Configurable via env (default: none — persists forever) | Auto-recycles at 4 hours or 75 requests |
| Piper idle timeout | 15 min implicit session timeout | N/A (single daemon) |
| Session isolation | Multiple named sessions, separate instances | Single session per daemon |
| API surface | Full CLI (50+ commands) | Tiny HTTP API: `/health` + `/command` (search, fetch, fetchMany) |
| Bot detection handling | None — up to the user | Sophisticated (fingerprinting, consent, Anubis, Cloudflare) |
| Search engine integration | None — you drive the browser | Built-in Google/DuckDuckGo with Cheerio parsing |
| Cost | Free browser automation; paid API key for web search | Free (uses real browser) |

### The Interception Mechanism

The `pi-agent-browser-native` extension uses three layers to steer agents toward agent_browser:

1. **Prompt-level guidance**: Injects `PROJECT_RULE_PROMPT` ("when browser automation is needed, prefer the native `agent_browser` tool"). Scans every user message via `shouldAppendBrowserSystemPrompt()` for patterns like "browse", "search the web", "open https://", "research online" — if matched, appends the full browser playbook to the system prompt. Explicitly says "Do not use browser automation to drive public search-engine forms such as Google for discovery."

2. **Bash guard**: Intercepts bash commands that look like `agent-browser` calls in the bash tool and redirects to the native tool with an error message ("Use the native agent_browser tool instead of bash for agent-browser in this environment.").

3. **`agent_browser_web_search` tool**: A separate pi tool using Brave/Exa APIs (paid). Has rate limiting, timeout, pagination, and explicit guidelines to prefer it over browser-based search. Disabled unless API keys are configured.

### Resource Consumption

If both systems ran simultaneously, per session:

| Component | RAM |
|---|---|
| agent-browser Rust daemon | ~26 MB |
| web-search Node.js daemon | ~40-60 MB |
| Chrome for Testing (agent-browser session) | ~200-400 MB |
| Chrome for Testing (web-search session) | ~200-400 MB |
| **Total (both active)** | **~500-900 MB** |

Both use the same Chrome for Testing binary at `~/.agent-browser/browsers/chrome-149.0.7827.22/`, but each spawns a **separate process** with its own profile, temp directory, and CDP port.

### What We Did

1. Diagnosed that `pi-agent-browser-native` was installed but the upstream `agent-browser` binary was missing
2. Installed `agent-browser@0.27.0`, then updated to `0.32.2` to match the extension's baseline
3. Installed **nvm** and **Node.js v24.18.0** (agent-browser 0.32.2 requires Node >=24)
4. Tested `agent_browser` on YouTube — confirmed it works with Chrome for Testing
5. Understood session lifecycle: daemon persists, each session = separate browser instance, no auto-cleanup without idle timeout
6. Cloned `ogulcancelik/agent-skills` repo and examined the `web-search` skill
7. Compared both systems in depth (architecture, daemon model, bot protection, search, lifecycle)
8. **Decided to uninstall agent-browser and the extension** in favor of the web-search skill for our resource-constrained system
9. Uninstalled `agent-browser` CLI globally, removed `npm:pi-agent-browser-native` from `settings.json`
10. Cloned the `pi-agent-browser-native` source repo into `opensource/` for reference
11. Set up the web-search skill with dependencies and symlinked it into `.agents/skills/`

### Related Files

- Extension source (cloned): `/home/anupam/Desktop/workspace/opensource/pi-agent-browser-native/`
- web-search skill: `/home/anupam/Desktop/workspace/opensource/agent-skills/skills/web-search/`
- Symlink: `/home/anupam/Desktop/workspace/.agents/skills/web-search/`
- Pi settings: `/home/anupam/.pi/agent/settings.json`
- Chrome for Testing: `~/.agent-browser/browsers/chrome-149.0.7827.22/`