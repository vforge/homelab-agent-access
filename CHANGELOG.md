# Changelog

All notable changes to this project are documented here.

## [Unreleased]

- Add an agent-facing skill with safe usage rules for the provisioning tools.
- Harden the provisioning transport and input serialization.
- Replace the interactive whitelist with a forced-command dispatcher.
- Replace wildcard sudoers rules with exact root-owned read-only helpers.
- Add disposable-host integration tests.

## [0.1.0] - 2026-07-12

Initial public baseline:

- Migrated the SSH readonly-user scripts from a dotfiles repository.
- Added public-repository documentation and security guidance.
- Added local validation and GitHub Actions CI.
