---
name: ssh-themistocles
description: Connect to the second system over SSH using the saved LAN target. Commands survive SSH drops via persistent tmux session.
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

## Operating rules

- do not store or print passwords
- if prompted for a password, let the user type it directly in terminal
- after connecting, verify identity quickly with `hostname && whoami && pwd`
- if host key changes, stop and ask before accepting a new fingerprint