# Agent instructions

This is a public repository containing security-sensitive remote provisioning
scripts. Read `README.md` and `SECURITY.md` before changing implementation.

## Safety rules

- Never add real hostnames, public IPs, usernames, home paths, email addresses,
  SSH keys, tokens, passwords, private keys, or logs.
- Use generic examples such as `root@server`, `agent`, and `~/.ssh/agent.pub`.
- Never run provisioning scripts against a real host during tests.
- Do not weaken SSH restrictions, sudoers validation, input validation, or file
  permissions without documenting the security trade-off.
- Treat all remote input and `SSH_ORIGINAL_COMMAND` values as untrusted.
- Do not use `eval`, `sh -c`, arbitrary shell interpolation, or wildcard sudo
  rules for user-controlled values.
- Keep host-specific configuration outside the repository.

## Validation

Run before proposing changes:

```bash
make test
make lint
bash -n bin/create
bash -n bin/list
bash -n bin/remove
bash -n remote/homelab-agent-dispatch remote/homelab-agent-dispatch-root
```

`make test` runs local syntax and request-validation tests without contacting a
host. `make lint` requires ShellCheck. `make integration` requires an ephemeral
Linux host and passwordless sudo.
Security-sensitive changes need disposable-host integration tests and an update
to `SECURITY.md` and the changelog.

## Change discipline

- Keep the current implementation clearly labeled experimental until its
  known limitations are fixed.
- Prefer one focused change per commit.
- Update command documentation whenever behavior changes.
- Review the staged diff for personal data and secrets before committing.
