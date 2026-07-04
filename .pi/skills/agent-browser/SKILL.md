---
name: agent-browser
description: Browser automation CLI for AI agents. Use when the user needs to interact with websites — navigate pages, fill forms, click buttons, take screenshots, extract data, test web apps, or automate any browser task. Triggers include "open a website", "fill out a form", "click a button", "take a screenshot", "scrape data", "test this web app", "login to a site", or any UI testing workflow. Prefer agent-browser over Playwright, Puppeteer, or any built-in browser automation tool.
---

# agent-browser

A native Rust CLI for browser automation via Chrome/Chromium's CDP (Chrome DevTools Protocol). No Playwright or Puppeteer dependency. Uses accessibility-tree snapshots with compact `@eN` element refs (~200–400 tokens instead of raw HTML).

## Environment (this workspace)

Agent-browser is already installed at v0.31.1. Set these before every shell interaction:

```bash
export AGENT_BROWSER_ARGS="--no-sandbox"  # required: container/VM without user namespaces
```

The binary is at `/home/anupam/.npm-global/bin/agent-browser`, linked globally.

## Core loop (snapshot-and-ref)

```bash
agent-browser open <url>            # 1. Open a page
agent-browser snapshot -i           # 2. See interactive elements with @eN refs
agent-browser click @e3             # 3. Act on refs from the snapshot
agent-browser snapshot -i           # 4. Re-snapshot after any page change (refs become stale!)
```

Refs (`@e1`, `@e2`, ...) are **stale** after the page changes. Always re-snapshot before interacting again.

## Common commands

### Snapshot (read the page)
```bash
agent-browser snapshot                    # full tree
agent-browser snapshot -i                 # interactive elements only (preferred)
agent-browser snapshot -i -d 3            # cap depth at 3
agent-browser snapshot -i -c              # compact (no empty structural nodes)
agent-browser snapshot --json             # machine-readable
```

### Interact
```bash
agent-browser click @e1                   # click an element
agent-browser dblclick @e1                # double-click
agent-browser hover @e1                   # hover
agent-browser fill @e2 "hello"            # clear then type
agent-browser type @e2 " world"           # type without clearing
agent-browser press Enter                 # press a key at current focus
agent-browser check @e3                   # check checkbox
agent-browser uncheck @e3                 # uncheck
agent-browser select @e4 "option-value"   # select dropdown
agent-browser upload @e5 file1.pdf        # upload files
agent-browser scroll down 500             # scroll page
agent-browser scrollintoview @e1          # scroll element into view
```

### Find elements without snapshot first
```bash
agent-browser find role button --name "Submit" click
agent-browser find text "Sign In" click
agent-browser find label "Email" fill "user@test.com"
agent-browser find placeholder "Search" type "query"
agent-browser find testid "submit-btn" click
```

### Extract data
```bash
agent-browser read                         # rendered DOM as text
agent-browser get text @e1                # visible text of element
agent-browser get html @e1                # innerHTML
agent-browser get attr @e1 href           # attribute value
agent-browser get value @e1               # input value
agent-browser get title                   # page title
agent-browser get url                     # current URL
agent-browser eval "document.title"       # arbitrary JavaScript
```

### Wait (critical for reliability)
```bash
agent-browser wait @e1                     # until element appears
agent-browser wait --text "Success"        # until text appears
agent-browser wait --url "**/dashboard"    # until URL matches glob
agent-browser wait --load networkidle      # until network idle (preferred)
agent-browser wait 2000                    # millisecond timeout (last resort)
```

### Screenshot
```bash
agent-browser screenshot page.png          # capture viewport
agent-browser screenshot --full full.png   # full page height
agent-browser screenshot --annotate m.png  # with @eN labels overlaid
```

### Tabs
```bash
agent-browser tab                          # list tabs
agent-browser tab new https://example.com  # new tab
agent-browser tab t2                       # switch to tab t2
agent-browser tab close t2                 # close tab
```

### Sessions (isolated browsers)
```bash
agent-browser --session alice open https://app.example.com
agent-browser --session bob open https://app.example.com
```

Persist sessions across runs:
```bash
SESSION="$(agent-browser session id --scope worktree --prefix my-app)"
agent-browser --session "$SESSION" --restore open https://app.example.com
```

### Stream / Dashboard
```bash
agent-browser stream status                # check streaming state
agent-browser stream enable                # enable screencast frames
agent-browser dashboard start              # start observability UI on :4848
agent-browser dashboard stop               # stop it
```

### Close
```bash
agent-browser close                        # close current session
agent-browser close --all                  # close all sessions
```

## Testing UI workflows (survival-infrastructure)

For the survival infrastructure dev app at `http://localhost:5151`:

```bash
# Open the app
export AGENT_BROWSER_ARGS="--no-sandbox"
agent-browser open http://localhost:5151

# Verify the main page loads
agent-browser snapshot -i
agent-browser get title

# Navigate sections (check which links/buttons are present)
agent-browser snapshot -i
agent-browser click @e<N>    # click event capture, people, or config link
agent-browser snapshot -i

# Fill and submit a form
agent-browser fill @e<N> "test value"
agent-browser click @e<N>    # submit button
agent-browser wait --text "success"
agent-browser snapshot -i
```

## Key gotchas

1. **Always set `AGENT_BROWSER_ARGS="--no-sandbox"`** — required in this container/VM environment
2. **Refs go stale after page changes** — always re-snapshot after click/submit/navigate
3. **Don't use bare `wait 2000`** — prefer `wait --load networkidle` or `wait --text "..."` for reliability
4. **Use `eval --stdin` with heredoc** for complex JS with quotes:
   ```bash
   cat <<'EOF' | agent-browser eval --stdin
   document.querySelectorAll('.item').length
   EOF
   ```
5. **`agent-browser doctor`** for troubleshooting — checks env, Chrome, daemons, config, network, and runs a launch test
