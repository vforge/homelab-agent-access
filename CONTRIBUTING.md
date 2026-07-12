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
```

Do not test against real machines. Use a disposable VM or container for
integration tests and provide setup instructions that do not require committed
credentials.

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
