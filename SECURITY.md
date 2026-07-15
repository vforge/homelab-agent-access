# Security policy

## Project status

This repository contains scripts that make privileged changes on remote
machines. It is personal homelab tooling, provided as-is, and is not a
complete security boundary for hostile or prompt-injectable agents.

The current design uses an SSH forced-command dispatcher and a root-owned helper
with a small validated request protocol. It deliberately reuses the target's
existing sshd rather than installing a resident API daemon or observability
control plane. It is safer than the previous interactive `rbash` design, but it
is still not a VM, container, MAC policy, or complete sandbox.

[`ARCHITECTURE.md`](ARCHITECTURE.md) records the accepted design direction,
trust boundaries, required invariants, alternatives considered, and conditions
under which a centralized telemetry gateway should replace this model.

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
- Provisioning preflights managed files, refuses unproven fixed helper paths,
  validates existing managed file ownership, modes, formats, helper SHA-256
  digests, and sudoers content, installs replacements atomically, and rolls them
  back on failure.
- Usernames, public keys, allowlist unit names, request unit names, and log
  limits are validated.
- Root-owned per-host status and log allowlists are checked by the root helper.
- Existing unmanaged accounts, pre-existing homes for new accounts, and
  authorized-key entries are not overwritten or adopted.
- Managed-account metadata binds the username to a nonzero UID and canonical
  `/home/USER` path before update or removal.
- The agent key uses OpenSSH `restrict` plus explicit forwarding, X11, PTY,
  agent-forwarding, and user-rc restrictions.
- The account has an impossible password hash (without locking public-key
  access), and its home/SSH files are root-owned.
- Managed metadata and allowlists are root-only readable. The public
  `authorized_keys` file is root-owned and read-only but readable by sshd's
  unprivileged account lookup.
- The only sudo permission is an exact no-argument root helper.
- The root helper uses fixed absolute command paths and does not evaluate shell
  input.
- Provisioning records root-only SHA-256 digests for the installed dispatcher
  and privileged helper. Updates and `bin/list` compare helper content with that
  manifest.

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
- Status and log allowlists are currently host-wide, not per identity; multiple
  managed agents on one host therefore share those policy scopes.
- Helper digest attestation detects drift from the last successful
  provisioning; it is not protection from trusted root, which can modify both
  files and digests. A one-time migration without a manifest recognizes secure
  helpers by their management header before replacing and attesting them.
- If an account is already absent, stale-state removal validates the metadata
  shape and exact sudoers content before deleting those two files. It cannot
  compare the recorded UID with absent passwd state and deliberately does not
  remove a home in this path.
- The system has no built-in request audit trail or server-side output
  redaction; agent-side minimization is not a technical confidentiality
  boundary.

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
- Confirm `bin/list` reports valid metadata, key, sudoers, allowlist, helper
  manifest, and helper-content states.
- Confirm only the managed authorized key is present.
- Confirm helper files, allowlists, and their parent directories are root-owned
  and not writable by the agent.
- Confirm no host-specific data or credentials are in the repository.
- Rotate or revoke the agent key after testing.
