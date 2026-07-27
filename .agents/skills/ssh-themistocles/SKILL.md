---
name: ssh-themistocles
description: Connect to the second system over SSH using the saved LAN target. Commands survive SSH drops via persistent tmux session.
disable-model-invocation: true
---

# SSH Themistocles

Use this skill when asked to:

- connect to the second system
- run commands on the Debian host at `192.168.0.122`
- run long or critical remote commands that must survive SSH disconnections

## Saved target

- user: `anupam`
- host: `192.168.0.122`
- SSH alias: `themistocles-lan`
- expected remote hostname: `themistocles`
- observed distro banner: Debian GNU/Linux (kernel `6.12.86+deb13-amd64`)

## Auth status

- passwordless SSH via local key: `~/.ssh/id_ed25519`
- public key installed on remote user: `anupam@192.168.0.122`

## Resilient remote commands (survives SSH drops)

For long-running or critical commands, run them inside a persistent tmux session on the remote. The session survives any SSH disconnection — commands keep running and output is captured when you reconnect.

### One-time setup (run once per agent session)

```bash
ssh themistocles-lan "tmux new -d -s pi-session 2>/dev/null || true"
```

### Sending a command

Use `tmux send-keys` to type the command into the persistent session. The `===END_rc=N===` marker captures the exit code.

```bash
ssh themistocles-lan \
  'tmux send-keys -t pi-session "YOUR_COMMAND; echo ===END_rc=\$?===" Enter'
```

### Waiting and reading output

```bash
# Poll until end marker appears on last line
while ! ssh themistocles-lan "tmux capture-pane -pS - -t pi-session | grep -q '===END_rc='" 2>/dev/null; do
  sleep 2
done

# Read full output (exit code is in last ===END_rc=N=== line)
ssh themistocles-lan "tmux capture-pane -pS - -t pi-session"
```

### When to use which

| Scenario | Use |
|---|---|
| Short commands (< 10s) | Plain `ssh themistocles-lan "cmd"` |
| Long commands (> 10s) | tmux session |
| Network is unstable | tmux session |
| Commands that must not be interrupted | tmux session |

### Cleanup (optional)

```bash
ssh themistocles-lan "tmux kill-session -t pi-session 2>/dev/null || true"
```

## Proven achievement: remote workspace restore

On **2026-06-25**, this tmux persistence workflow was proven in production:
a full Phase 1 workspace restore (14 repos + 13MB critical snapshot) was
run on `themistocles` over a fragile WiFi link (3.6s latency spikes,
frequent SSH drops). The restore took ~2+ hours and survived multiple
complete SSH disconnections without interruption.

### What was restored

| Category | Details |
|---|---|
| Git repos | 14 repos cloned (including `resume`) |
| Critical snapshot | SQLite DBs, hermes session state, graphify-out dirs, runtime data |
| Source | GitHub Release (`snapshot-critical` tag) |

### Command sequence used

```bash
# 1. Create persistent session
ssh themistocles-lan "tmux new -d -s pi-session"

# 2. Send the restore command (token injected at send-time)
ssh themistocles-lan \
  'tmux send-keys -t pi-session "export GP=TOKEN && bash /tmp/wpb/bootstrap-orchestrator.sh --dest \$HOME/workspace --bootstrap-dir /tmp/wpb --github-token \$GP; echo ===END_rc=\$?===" Enter'

# 3. Poll for completion (survives any number of SSH drops)
while ! ssh themistocles-lan "tmux capture-pane -pS - -t pi-session | grep -q '===END_rc='" 2>/dev/null; do
  sleep 30  # longer interval for long-running jobs
done

# 4. Capture output
ssh themistocles-lan "tmux capture-pane -pS - -t pi-session"
```

### Key lesson

`tmux send-keys` is the correct approach for fragile connections.
Piping commands via SSH stdin (`echo "cmd" | ssh host`) does NOT survive
drops — the remote shell receives SIGHUP when the pipe breaks.
`tmux send-keys` decouples command execution from the SSH session entirely.

## Health check — diagnose a stuck or hanging session

If `pi-session` seems unresponsive or a command never finishes, run these
checks before escalating.

### 1. Is tmux itself alive?

```bash
ssh themistocles-lan 'tmux list-sessions'
```

Expected output shows `pi-session: 1 windows (created ...)`. If the session
doesn't appear, it was killed — start a new one with `tmux new -d -s pi-session`.

### 2. What's in the scrollback?

```bash
ssh themistocles-lan 'tmux capture-pane -pS -10 -t pi-session'
```

Shows the last 10 lines. If it looks stale (same output as minutes ago), the
shell inside may be blocked.

### 3. What processes are running inside the session?

Inject a `ps` command to see the process tree:

```bash
ssh themistocles-lan 'tmux send-keys -t pi-session "ps -o pid,ppid,state,cmd --forest | head -20" Enter'
sleep 2
ssh themistocles-lan 'tmux capture-pane -pS -30 -t pi-session'
```

Look for:
- `D` (uninterruptible sleep) or `T` (stopped) — likely stuck
- `R` running for many minutes — may be in an infinite loop
- `Z` (zombie) — parent hasn't reaped it

### 4. Quick resource scan

```bash
ssh themistocles-lan 'ps aux --sort=-%cpu | head -5; echo "---"; free -h | head -2'
```

### How to fix common problems

| Problem | Fix |
|---|---|
| Process unresponsive (hanging on network) | `kill <PID>` — kills just the child, shell resumes |
| Shell frozen, won't read input | `tmux send-keys -t pi-session C-c` — sends Ctrl+C |
| Shell completely dead | `tmux send-keys -t pi-session C-d` — closes the shell, window exits |
| Everything broken | `tmux kill-session -t pi-session` then `tmux new -d -s pi-session` |
| Process stuck due to `subprocess.run()` with no timeout | Add `timeout=60` to the call (known issue: `sync_repos.py` `git fetch --all --prune` has no timeout) |

### Prevention — add timeouts to remote commands

When sending commands into tmux, wrap long-running operations with `timeout`
so they don't hang forever if the network stalls:

```bash
# Good — gives up after 60 seconds
ssh themistocles-lan 'tmux send-keys -t pi-session \
  "timeout 60 git fetch origin main && echo DONE || echo TIMEOUT" Enter'

# Bad — can hang indefinitely
ssh themistocles-lan 'tmux send-keys -t pi-session \
  "git fetch origin main && echo DONE" Enter'
```

## Operating rules

- do not store or print passwords
- if prompted for a password, let the user type it directly in terminal
- after connecting, verify identity quickly with `hostname && whoami && pwd`
- if host key changes, stop and ask before accepting a new fingerprint