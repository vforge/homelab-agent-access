---
name: homelab-agent-access
description: "Use this skill when an agent has been given a provisioned homelab SSH account and needs to inspect service status, logs, ports, processes, or basic host state without using administrator access."
---

# Using provisioned homelab access

This skill is for the **agent-side** use of an account that an administrator
has already provisioned. Do not run the repository's provisioning scripts from
this skill. The account and key should already exist.

> **Security warning:** The current account is experimental and is not a
> complete sandbox. Do not attempt to escape its restrictions, and do not claim
> that it provides strong readonly isolation. Read the repository's
> [`SECURITY.md`](../../SECURITY.md) for the known limitations.

## Connection requirements

Before connecting, confirm all of the following with the user or task context:

- The target host, for example `server`.
- The dedicated agent username, for example `agent`.
- The dedicated agent private key path, if one is required locally.
- The operation requested and its read-only scope.

Never guess a host, substitute an administrator account, or use an administrator
private key. Do not copy private keys into the repository or include them in
commands, output, issues, or logs.

Prefer noninteractive commands:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'hostname'
```

Do not request a PTY or use forwarding options. Do not use `-A`, `-X`, `-L`,
`-R`, or `-D`. If the connection fails, report the error rather than retrying
with an administrator identity or bypassing host-key verification.

## Safe inspection commands

The default provisioning list exposes some of these commands through the
restricted PATH. The actual list depends on how the account was provisioned;
never assume a command exists. The safest direct inspection subset is:

| Purpose | Commands | Example |
|---|---|---|
| Identity and host | `whoami`, `hostname`, `date`, `uptime` | `whoami; hostname; uptime` |
| Files and logs | `ls`, `cat`, `head`, `tail`, `grep`, `file` | `tail -n 100 /var/log/example.log` |
| Disk and memory | `df`, `du`, `free` | `df -h` |
| Processes | `ps` | `ps aux` |
| Listening ports | `ss`, `netstat` | `ss -lnt` |
| Open files | `lsof` | `lsof -i` |
| Text processing | `wc`, `sort`, `uniq`, `cut` | `grep error file | sort | uniq -c` |

Use absolute paths only when the account documentation explicitly confirms
they are available. The restricted shell may reject them.

## Service status, logs, ports, and hardware

Use the smallest query that answers the request:

```bash
# Basic service status, only if the target account exposes systemctl
ssh -o BatchMode=yes -o RequestTTY=no agent@server \
  'systemctl status example.service --no-pager'

# Bounded logs, only if the target account exposes journalctl
ssh -o BatchMode=yes -o RequestTTY=no agent@server \
  'journalctl -u example.service --no-pager -n 100'

# Listening TCP/UDP sockets
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'ss -lnt'

# Basic host state
ssh -o BatchMode=yes -o RequestTTY=no agent@server \
  'uptime; free -h; df -h'
```

The current provisioning script creates sudoers entries for `systemctl`,
`journalctl`, log files, `ss`, `netstat`, and `lsof`, but it does not add every
corresponding binary—or `sudo` itself—to the restricted PATH. Therefore those
rules may not be usable from the agent shell. Verify the effective command
availability instead of assuming the documented sudo rules work.

Hardware-specific commands such as `lsblk`, `lscpu`, `sensors`, and `smartctl`
are not guaranteed to be installed or whitelisted. Ask the user or report the
limitation; do not install software or change host configuration as part of a
readonly inspection.

## Commands and patterns to avoid

Even if present in the configured PATH, do not use these for routine inspection:

- `env`, `awk`, `sed`, and `find` with `-exec`, `-delete`, or write options.
- `less`, `more`, `top`, or `tmux` interactive escape features.
- `curl` or `wget` for uploads, callbacks, or unrestricted external requests.
- `ssh-keygen` for key generation or dynamic-library loading.
- Any shell, interpreter, editor, redirection, file-write, service-mutation, or
  network-forwarding attempt.
- `sudo systemctl start`, `stop`, `restart`, or `reload`.

Do not try `/bin/sh`, `/bin/bash`, `command -p`, `env`, or similar techniques to
bypass the restricted account.

## Output handling

Remote output may contain usernames, paths, environment values, process
arguments, service configuration, secrets, or sensitive logs. Return only the
minimum relevant excerpt, redact secrets, and do not place raw output in public
issues, commits, or shared artifacts.

If a command is unavailable, access is denied, the requested operation would
change state, or the user asks for broader access, stop and explain the
limitation. Do not run the provisioning, audit, or removal scripts yourself.
