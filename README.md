# Homelab Agent Access

Small, SSH-based tooling for giving an agent intentionally constrained access to
homelab machines for service, log, network, and hardware inspection.

[![CI](https://github.com/vforge/homelab-agent-access/actions/workflows/ci.yml/badge.svg)](https://github.com/vforge/homelab-agent-access/actions/workflows/ci.yml)

> **Status: experimental.** The current scripts are a migrated baseline, not a
> complete security boundary for untrusted or prompt-injectable agents. Read
> [SECURITY.md](SECURITY.md) before deploying them.

## Scope

The current baseline provisions a separate SSH user with:

- A restricted Bash login shell and a command-path whitelist.
- SSH authorized-key forwarding restrictions.
- Optional, limited sudo rules for service and log inspection.
- Create, audit, key-rotation, and removal workflows.

This project intentionally installs no monitoring daemon or agent package on
remote machines. It assumes the required operating-system tools already exist.

## Quick start

### Requirements

- Bash and OpenSSH on the administering machine.
- A privileged SSH login to the target. The current scripts perform privileged
  operations directly and do not automatically invoke `sudo`.
- A Debian/Ubuntu or Arch-like target, or a target with compatible `useradd`,
  `adduser`, `chsh`, and `sudo` tools.
- A public SSH key stored outside this repository.

Run the local syntax checks first:

```bash
make test
```

Provision an account, inspect it, and remove it later:

```bash
./bin/ssh-readonly-user/create root@server ~/.ssh/agent.pub --user agent
./bin/ssh-readonly-user/list root@server
./bin/ssh-readonly-user/list root@server --json
./bin/ssh-readonly-user/remove root@server agent
```

See [`bin/ssh-readonly-user/README.md`](bin/ssh-readonly-user/README.md) for
command options and the current remote changes.

## Security model

The intended operator is an administrator provisioning a dedicated account for
a trusted environment. The agent key should be treated as a separate,
revocable identity—not as an administrator key.

The current implementation is **not suitable as a hard security boundary** for
an untrusted agent. In particular, `rbash` and a PATH whitelist are bypassable,
the current sudo rules are broader than readonly access, and the optional home
lock is only defense in depth.

The planned direction is a forced-command dispatcher with root-owned helpers
that accept a small, validated set of read-only operations. Until that work is
complete, do not deploy this baseline to production or to hosts where the agent
may be actively adversarial.

## Repository layout

```text
.
├── bin/ssh-readonly-user/  # Current provisioning, audit, and removal scripts
├── tests/                  # Local validation helpers
├── AGENTS.md               # Instructions for automated contributors
├── CONTRIBUTING.md         # Contribution and validation workflow
├── SECURITY.md             # Threat model, limitations, and reporting
└── Makefile                # Local test entry point
```

## Development

Changes to remote execution, SSH options, sudoers, filesystem permissions, or
input parsing are security-sensitive. Keep changes small and document the
threat-model impact.

```bash
make test
bash -n bin/ssh-readonly-user/create
bash -n bin/ssh-readonly-user/list
bash -n bin/ssh-readonly-user/remove
```

Tests must not contact real machines. Use disposable VMs or containers for
integration testing and never commit host-specific configuration, credentials,
private keys, or real logs.

## License

MIT. See [LICENSE](LICENSE).
