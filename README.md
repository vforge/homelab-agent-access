# Homelab Agent Access

Restricted, read-oriented SSH access for agents inspecting homelab machines.

> **Status:** Work in progress. The current scripts are a migrated baseline and
> are not yet a complete security boundary for untrusted agents. Review and
> harden the dispatcher, SSH transport, and privilege rules before deployment.

## Contents

- `bin/ssh-readonly-user/` — provisioning, audit, and removal scripts.

## Design goals

- Separate agent identities from administrator access.
- Permit service status, selected logs, port, and hardware inspection.
- Avoid installing a monitoring stack on each machine.
- Keep host-specific inventory and credentials out of this repository.

## Planned hardening

- Replace the interactive `rbash`/PATH whitelist with a forced-command dispatcher.
- Use exact root-owned read-only helpers instead of wildcard sudo rules.
- Safely serialize provisioning inputs over SSH.
- Add shell tests and disposable-host validation.
