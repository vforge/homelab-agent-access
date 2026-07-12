# ssh-readonly-user

Provision and audit a separate SSH account for read-oriented inspection of a
homelab machine.

> **Security warning:** This is an experimental baseline, not a complete
> security boundary for untrusted agents. `rbash`, the command whitelist, and
> home locking are defense-in-depth measures only. Review the repository
> [security policy](../../SECURITY.md) before deployment.

## Commands

### Create or update

```bash
./create root@server ~/.ssh/agent.pub --user agent
```

Options:

- `--user <name>` — choose the remote account name.
- `--commands "cmd1,cmd2,..."` — replace the default command list.
- `--lock-home` — attempt to make the home directory non-writable.
- `--unlock-home` — undo the home-directory lock.

The script is intended to support repeated provisioning, key rotation, and
command-list updates. Validate changes on a disposable target first.

### Audit

```bash
./list root@server
./list root@server --brief
./list root@server --json
```

The audit command reports accounts using an `rbash` login shell, available
whitelist entries, authorized-key metadata, sudoers entries, and home
permissions.

### Remove

```bash
./remove root@server agent
./remove root@server agent --keep-home
```

Removal deletes the generated sudoers file, restricted authorized-key entries,
and the account. `--keep-home` leaves the home directory in place.

## Current remote changes

The current baseline may modify:

- A dedicated user account and its login shell.
- `~agent/.readonly-bin/` symlinks for the selected commands.
- `~agent/.profile` and `~agent/.bashrc`.
- `~agent/.ssh/authorized_keys`.
- `/etc/sudoers.d/readonly-agent`.
- Optional home-directory permissions and filesystem attributes.

The scripts currently require a privileged SSH login; they do not automatically
use `sudo` for the provisioning connection.

## Known limitations

- SSH argument serialization in the provisioning path needs hardening.
- `rbash` and a PATH whitelist are not a robust sandbox.
- Several default commands can provide shell escapes, file writes, or network
access.
- The sudoers rules include mutating service operations and broad wildcards.
- The optional home lock does not guarantee that every created file is
non-writable.
- Host-key handling currently uses `StrictHostKeyChecking=accept-new`.

These limitations are tracked at the repository level. Do not use the current
baseline for hostile or untrusted agents.
