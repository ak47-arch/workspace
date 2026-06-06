---
name: ssh-themistocles
description: Connect to the second system over SSH using the saved LAN target and verify session identity.
---

# SSH Themistocles

Use this skill when asked to:

- connect to the second system
- run commands on the Debian host at `192.168.0.122`
- avoid re-providing SSH target details each time

## Saved target

- user: `anupam`
- host: `192.168.0.122`
- expected remote hostname: `themistocles`
- observed distro banner: Debian GNU/Linux (kernel `6.12.86+deb13-amd64`)

## Auth status (configured)

- passwordless SSH is enabled via local key: `~/.ssh/id_ed25519`
- public key installed on remote user: `anupam@192.168.0.122`
- login verified with batch mode (no password fallback):

```bash
ssh -o BatchMode=yes -o PasswordAuthentication=no anupam@192.168.0.122 "hostname && whoami"
```

Expected output:

- hostname: `themistocles`
- user: `anupam`

## Preferred command

```bash
ssh anupam@192.168.0.122
```

## Operating rules

- do not store or print passwords
- if prompted for a password, let the user type it directly in terminal
- after connecting, verify identity quickly with:

```bash
hostname && whoami && pwd
```

- if host key changes, stop and ask before accepting a new fingerprint

## Optional convenience (user-approved)

If the user asks to avoid typing the full SSH command each time, or asks for an SSH alias or config entry, suggest adding the following block to `~/.ssh/config`:

Before suggesting the config block, note that the user should check whether a `Host themistocles-lan` entry already exists in `~/.ssh/config` (for example: `grep -A5 "themistocles-lan" ~/.ssh/config`). If it exists with different values, instruct the user to edit the existing entry rather than append a duplicate `Host` block.

```sshconfig
Host themistocles-lan
  HostName 192.168.0.122
  User anupam
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

Then connect with:

```bash
ssh themistocles-lan
```

Validate alias is passwordless:

```bash
ssh -o BatchMode=yes themistocles-lan "hostname && whoami"
```