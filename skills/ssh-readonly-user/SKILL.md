---
name: ssh-readonly-user
description: "Use this skill when a user asks to provision, audit, rotate, or remove the experimental SSH access account from a homelab machine. The tools make privileged remote changes and must not be treated as a secure sandbox."
---

# Homelab SSH access tools

This skill covers the scripts in `bin/ssh-readonly-user/`. They provision and
audit a separate SSH account intended for read-oriented inspection of homelab
machines.

## Important safety boundary

This is a personal, experimental project. The current implementation is not a
complete security boundary for an untrusted or prompt-injectable agent. Read
[`SECURITY.md`](../../SECURITY.md) before using it.

The scripts can make privileged remote changes, including changing users,
SSH keys, shells, home permissions, and sudoers. Never run them against a real
host unless the user explicitly requested that operation and supplied the
intended target.

Do not:

- Use a real private key as input. Only a public key file such as
  `~/.ssh/agent.pub` is expected.
- Invent a hostname, username, key path, or service name.
- Run `remove` without explicit confirmation because it deletes remote access.
- Treat `rbash`, the command whitelist, or `--lock-home` as a sandbox.
- Claim that the provisioned account is truly readonly.
- Paste logs, host inventory, key material, or command output into public
  issues or commits.

## Locate the tools

From a checkout of this repository:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
CREATE="$REPO_ROOT/bin/ssh-readonly-user/create"
LIST="$REPO_ROOT/bin/ssh-readonly-user/list"
REMOVE="$REPO_ROOT/bin/ssh-readonly-user/remove"
```

Run validation before using a new checkout:

```bash
make test
```

## Operations

### Provision or update an account

Only do this after confirming the remote target, administrator login, public
key path, account name, and requested command list with the user:

```bash
"$CREATE" root@server ~/.ssh/agent.pub --user agent
```

The current script expects a privileged SSH login. It does not automatically
invoke `sudo` on the remote provisioning connection. Re-running it is intended
to update the key and command list, but the SSH argument serialization path is
currently a known limitation; do not use it for production provisioning until
that issue is fixed.

### Audit provisioned accounts

```bash
"$LIST" root@server
"$LIST" root@server --brief
"$LIST" root@server --json
```

Treat the output as potentially sensitive host data. Use `--json` only when a
machine-readable result is needed.

### Remove an account

Removal is destructive. Confirm the exact host and account before running:

```bash
"$REMOVE" root@server agent
```

Use `--keep-home` only when the user explicitly wants the remote home directory
preserved:

```bash
"$REMOVE" root@server agent --keep-home
```

## After provisioning

The provisioned account is intended to expose a restricted shell and selected
inspection tools. The current baseline also creates broad, partly mutating
sudoers rules; do not describe this as readonly access or grant the key to an
untrusted agent.

For service status, logs, ports, or hardware inspection, first verify which
commands and sudo rules were actually installed on the target. Do not assume
that a documented command is available or safe on every operating system.

## Escalate instead of guessing

Ask the user for clarification when:

- The host, admin login, account name, or public key is ambiguous.
- The user has not authorized a destructive operation.
- The request requires service mutation, arbitrary command execution, or access
  beyond the documented inspection scope.
- The target is production, internet-facing, or outside the user's homelab.
- The output includes secrets or sensitive host data that would need to be
  shared publicly.
