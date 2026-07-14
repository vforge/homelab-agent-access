# Security policy

## Project status

This repository contains scripts that make privileged changes on remote
machines. It is personal homelab tooling, provided as-is, and is not a
complete security boundary for hostile or prompt-injectable agents.

The current design uses an SSH forced-command dispatcher and a root-owned helper
with a small validated request protocol. It is safer than the previous
interactive `rbash` design, but it is still not a VM, container, MAC policy, or
complete sandbox.

## Threat model

The intended use is a dedicated, revocable identity for an agent operating in a
trusted homelab. The agent may be accidentally misled or its key may be
compromised, so it must not share administrator credentials.

The current account can request allowlisted service state, allowlisted service
logs, listening sockets, and selected hardware information. Logs and host
metadata may contain secrets. A compromised key can query all operations exposed
by the helper.

## Current security properties

- Provisioning payloads are encoded before being passed through SSH arguments.
- Provisioning preflights managed files, validates sudoers before installation,
  installs file replacements atomically, and rolls them back on failure.
- Usernames, public keys, allowlist unit names, request unit names, and log
  limits are validated.
- Root-owned per-host status and log allowlists are checked by the root helper.
- Existing unmanaged accounts and authorized-key entries are not overwritten.
- Managed-account metadata binds the username to a nonzero UID and canonical
  `/home/USER` path before update or removal.
- The agent key uses OpenSSH `restrict` plus explicit forwarding, X11, PTY,
  agent-forwarding, and user-rc restrictions.
- The account password is locked and its home/SSH files are root-owned.
- Managed metadata, authorized keys, and allowlists are root-only readable.
- The only sudo permission is an exact no-argument root helper.
- The root helper uses fixed absolute command paths and does not evaluate shell
  input.

## Remaining limitations

- The administrator must maintain the allowlists; an allowlisted unit can still
  expose sensitive state or logs.
- `journalctl` output may contain credentials or other sensitive information.
- Hardware output may reveal inventory and serial-adjacent information.
- The implementation is Linux-oriented and assumes GNU user-management tools.
- The root helper still runs with the host's normal root privileges.
- No resource, time, output-size, or network-egress sandbox is applied around
  the helper commands.
- The account should have only the managed authorized key. Additional access
  paths or host-level SSH configuration can weaken the design.

Do not add service mutation, arbitrary file reads, arbitrary command arguments,
or shell interpretation to the protocol without a separate security review.

## Reporting a vulnerability

Please do not disclose exploitable details in a public issue. Use GitHub's
private vulnerability reporting for this repository when available:

<https://github.com/vforge/homelab-agent-access/security/advisories/new>

Include the affected file, a minimal reproduction, impact, and a suggested
fix. Do not include credentials, private keys, real host data, or sensitive
logs.

## Security review checklist

Before deployment or release:

- Test on a disposable host.
- Confirm host keys are verified out of band.
- Confirm the dedicated key cannot forward, open a PTY, or run arbitrary shell
  commands.
- Inspect and validate every sudoers rule with `visudo`.
- Confirm `bin/list` reports valid metadata, key, sudoers, and allowlist states.
- Confirm only the managed authorized key is present.
- Confirm helper files, allowlists, and their parent directories are root-owned
  and not writable by the agent.
- Confirm no host-specific data or credentials are in the repository.
- Rotate or revoke the agent key after testing.
