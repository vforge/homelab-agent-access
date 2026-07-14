# Changelog

All notable changes to this project are documented here.

## [Unreleased]

- Add disposable-host integration tests.
- Add per-host service and log allowlists.
- Bind managed accounts to recorded UID and canonical home metadata.
- Preflight provisioning and roll back failed managed-file installations.
- Strengthen managed-state auditing, file permissions, and SSH key restrictions.
- Add ShellCheck validation to local tooling and CI.
- Keep password authentication disabled without locking SSH public-key access.

## [0.2.0] - 2026-07-12

- Replace the interactive whitelist with a forced-command dispatcher.
- Replace wildcard sudoers rules with an exact no-argument root helper.
- Add fixed status, bounded logs, ports, and hardware operations.
- Add an agent-facing skill for using the provisioned account.
- Harden provisioning transport, account lifecycle, and input validation.
- Add local CLI and request-validation tests.

## [0.1.0] - 2026-07-12

Initial public baseline:

- Migrated the SSH readonly-user scripts from a dotfiles repository.
- Added public-repository documentation and security guidance.
- Added local validation and GitHub Actions CI.
