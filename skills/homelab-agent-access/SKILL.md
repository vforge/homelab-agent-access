---
name: homelab-agent-access
description: "Use this skill when an agent has been given a provisioned homelab SSH account and needs to inspect service status, logs, ports, or hardware without administrator access."
---

# Using provisioned homelab access

This skill is for the **agent-side** use of an account that an administrator
has already provisioned. Do not run `bin/create`, `bin/list`, or `bin/remove`
from this skill. The account and dedicated key should already exist.

> **Security warning:** The account is experimental and is not a complete OS
> sandbox. Do not attempt to escape its restrictions or claim stronger isolation
> than the repository's [`SECURITY.md`](../../SECURITY.md) provides.

## Connection requirements

Confirm all of the following with the user or task context:

- Target host, such as `server`.
- Dedicated agent username, such as `agent`.
- Dedicated agent private-key path, if one is required locally.
- The requested read-only operation.

Never guess a host, substitute an administrator account, or use an administrator
private key. Do not copy private keys into the repository or include them in
commands, output, issues, or logs.

Prefer noninteractive commands:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'status example.service'
```

Do not use `-A`, `-X`, `-L`, `-R`, or `-D`. If the connection fails, report the
error rather than retrying with an administrator identity or bypassing host-key
verification.

## Supported operations

The forced dispatcher accepts only these request forms:

```text
status UNIT
logs UNIT LINES
ports
hardware
```

### Service status

`UNIT` must be a systemd unit name included in the administrator's status
allowlist. The response is a fixed `systemctl show` view containing load and
active state fields:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server \
  'status example.service'
```

### Service logs

`UNIT` must be a systemd unit name included in the administrator's log
allowlist, and `LINES` must be between 1 and 500:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server \
  'logs example.service 100'
```

Logs can contain credentials, tokens, personal data, and internal paths. Return
only the minimum relevant excerpt and redact sensitive values.

### Listening ports

The helper runs a fixed `ss -lntup` query as root:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'ports'
```

Treat process names, command lines, addresses, and port mappings as potentially
sensitive host data.

### Hardware and host inventory

The helper attempts fixed read-only queries using any installed tools among
`lscpu`, `lsblk`, `free`, and `sensors`:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'hardware'
```

Missing tools produce partial output or an error. Do not install software or
change host configuration as part of an inspection request.

## What is not allowed

Do not:

- Run the provisioning, audit, or removal scripts yourself.
- Request an interactive shell, PTY, SSH forwarding, or administrator access.
- Request service mutation such as start, stop, restart, or reload.
- Try shell escapes, interpreters, editors, redirections, or arbitrary paths.
- Add command arguments outside the four documented request forms.
- Treat logs or hardware output as safe to publish without redaction.

If an operation is unavailable, denied by an allowlist, broader than this
interface, or would change state, stop and explain the limitation. Do not
bypass the dispatcher.
