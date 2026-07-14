# Homelab Agent Access

Small SSH tooling for giving an agent narrowly scoped access to homelab
machines for service, log, network, and hardware inspection.

[![CI](https://github.com/vforge/homelab-agent-access/actions/workflows/ci.yml/badge.svg)](https://github.com/vforge/homelab-agent-access/actions/workflows/ci.yml)

> **Status: experimental.** This is a personal homelab project, not a complete
> security boundary for hostile or prompt-injectable agents. Read
> [SECURITY.md](SECURITY.md) before deploying it.

## Personal project disclaimer

This is a personal homelab project published as-is for my own use. It may change,
break, or be replaced without notice. If you find it useful, great—but review
it carefully and adapt it to your machines, threat model, and operational
practices. It is not a supported product or security certification; you are
responsible for deployment and any resulting damage.

See [DISCLAIMER.md](DISCLAIMER.md) for the short version.

## How it works

An administrator runs the provisioning scripts once. They install:

1. A dedicated locked-password Unix account.
2. A root-owned SSH forced-command dispatcher.
3. A root-owned helper reachable only through an exact sudoers rule.
4. Root-owned per-host status and log unit allowlists.
5. An authorized key that disables forwarding, X11, PTY allocation, and user
   SSH rc files.

The agent then connects with the dedicated key and can request only these
operations:

```text
status UNIT
logs UNIT LINES
ports
hardware
```

The remote helper validates the request and runs fixed, read-oriented commands.
There is no intended interactive shell or arbitrary command interface.

## Quick start

### Requirements

- Bash and OpenSSH 7.2 or newer on the administering machine and target.
- A privileged SSH login to the target. The provisioning script performs root
  operations directly and does not automatically invoke `sudo`.
- A Linux target with `bash`, `useradd`, `usermod`, `getent`, `install`, `base64`,
  `sudo`, and `visudo`; Debian/Ubuntu and Arch-like systems are the targets.
- A public SSH key stored outside this repository.
- The target administrator's host key already present in `known_hosts`.

Run local checks first:

```bash
make test
```

Create host-specific unit allowlists outside this repository, one unit per
line, then provision, audit, and remove an account:

```bash
./bin/create root@server ~/.ssh/agent.pub --user agent \
  --status-allowlist /path/to/status-units.txt \
  --log-allowlist /path/to/log-units.txt
./bin/list root@server
./bin/list root@server --json
./bin/remove root@server agent
```

Blank and `#` comment lines are ignored. An empty allowlist denies its
operation; each file is limited to 65,536 bytes and 1,024 units. `status` and
`logs` requests for units absent from their respective allowlist are rejected;
`ports` and `hardware` are unaffected.

The scripts refuse to modify unmanaged existing accounts and preserve only
comments plus the managed key block in `authorized_keys`. See
[`bin/README.md`](bin/README.md) for the administrator command reference.

## Agent usage

After provisioning, use the dedicated agent identity—not an administrator key:

```bash
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'status example.service'
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'logs example.service 100'
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'ports'
ssh -o BatchMode=yes -o RequestTTY=no agent@server 'hardware'
```

See [`skills/homelab-agent-access/SKILL.md`](skills/homelab-agent-access/SKILL.md)
for agent-side operating instructions. Output may contain secrets or sensitive
host data; return only the minimum required and redact it before sharing.

## Security model and limitations

This design removes the interactive `rbash`/PATH whitelist and exposes a small
forced-command protocol instead. It is still not a VM, container, MAC policy,
or complete sandbox. In particular:

- Status and log unit names are restricted by root-owned per-host allowlists,
  but those lists must be reviewed and maintained by the administrator.
- Logs and hardware output may contain sensitive data.
- The helper depends on the target's systemd, journal, socket, and hardware
  tools being available.
- The implementation is Linux-oriented and assumes GNU user-management tools.
- A compromised dedicated key can still query everything exposed by the helper.
- The account and key should be used only for the intended homelab scope.

Do not add service mutation, arbitrary file reads, arbitrary command arguments,
or shell interpretation to the protocol without a separate security review.

## Repository layout

```text
.
├── bin/                    # Administrator provisioning, audit, and removal
├── remote/                 # Root-owned helper templates installed on targets
├── skills/                 # Agent-facing usage skill
├── tests/                  # Local validation helpers
├── AGENTS.md               # Instructions for automated contributors
├── CONTRIBUTING.md         # Contribution and validation workflow
├── SECURITY.md             # Threat model, limitations, and reporting
└── Makefile                # Local test entry point
```

## Development

Changes to SSH options, sudoers, remote parsing, filesystem ownership, or
helper commands are security-sensitive. Keep changes small and document the
threat-model impact.

```bash
make test
make lint         # requires ShellCheck
make integration  # requires an ephemeral Linux host and passwordless sudo
bash -n bin/create bin/list bin/remove
bash -n remote/homelab-agent-dispatch remote/homelab-agent-dispatch-root
```

Tests must not contact real machines. Use disposable VMs or containers for
integration tests and never commit host-specific configuration, credentials,
private keys, or real logs.

## License

MIT. See [LICENSE](LICENSE).
