# Security policy

## Project status

This repository contains scripts that make privileged changes on remote
machines. The current implementation is an experimental baseline and must not
be treated as a security boundary for hostile or prompt-injectable agents.

The recommended future design is an SSH forced-command dispatcher backed by
small, root-owned helpers that accept only validated read-only operations.

## Threat model

The intended use is a dedicated, revocable identity for an agent operating in a
trusted homelab. The agent may be accidentally misled or its key may be
compromised, so it must not share administrator credentials.

The current scripts do not fully protect against a determined user who can
execute commands as the provisioned account.

## Known limitations

- The provisioning script passes values through an SSH command invocation that
  does not safely preserve arbitrary argument boundaries.
- `rbash` and a private PATH are not a sandbox. Several allowlisted utilities
  have shell escapes, file-write features, or unrestricted network access.
- The generated sudoers rules contain broad wildcards and include service
  mutations such as start, stop, restart, and reload.
- `--lock-home` does not reliably make all existing files and nested directories
  non-writable.
- `eval` is used to resolve remote home directories.
- Host-key provisioning uses `StrictHostKeyChecking=accept-new`, which relies on
  first-use trust.
- Existing accounts and configuration files can be modified destructively.

Do not deploy the current baseline where these limitations are unacceptable.

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
- Confirm the agent key cannot forward, open a PTY, or run arbitrary commands.
- Inspect every sudoers rule and validate it with `visudo`.
- Confirm no host-specific data or credentials are in the repository.
- Rotate or revoke the agent key after testing.
