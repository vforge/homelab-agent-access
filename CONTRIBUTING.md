# Contributing

Thanks for helping improve Homelab Agent Access.

## Before changing code

Read:

- [`README.md`](README.md)
- [`AGENTS.md`](AGENTS.md)
- [`SECURITY.md`](SECURITY.md)

This project changes SSH access and remote privilege boundaries. Treat every
change as security-sensitive.

## Local validation

Run:

```bash
make test
make integration  # only on an ephemeral Linux host with passwordless sudo
```

Do not test against real machines. `tests/integration.sh` refuses existing
managed state but still creates accounts and global files; run it only on a
disposable VM, container, or CI runner. Never provide committed credentials.

## Pull requests

Please include:

- What changed and why.
- The threat-model impact.
- Tests run and their results.
- Documentation updates for changed behavior.
- Any remaining limitations or migration steps.

Do not include real hostnames, addresses, usernames, keys, tokens, passwords,
private paths, or logs in commits, tests, screenshots, or issue reports.

Keep pull requests focused and avoid unrelated formatting changes.
