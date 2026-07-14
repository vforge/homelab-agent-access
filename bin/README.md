# Administrator command reference

These commands provision and audit the agent account. They are for a trusted
administrator, not for the agent using the resulting account.

> **Security warning:** This is experimental homelab tooling. Test on a
disposable target, read [`SECURITY.md`](../SECURITY.md), and verify the remote
host key before provisioning.

## Create or update

Create one line-delimited allowlist file for each operation outside this
repository. Blank lines and lines beginning with `#` are ignored; an empty file
denies that operation. Each file is limited to 65,536 bytes and 1,024 units.

```text
# status-units.txt
example.service
```

```bash
./bin/create root@server ~/.ssh/agent.pub --user agent \
  --status-allowlist /path/to/status-units.txt \
  --log-allowlist /path/to/log-units.txt
```

Options:

- `--user <name>` — remote account name. If omitted, it is derived from the
  public-key filename.
- `--status-allowlist <file>` — allowed systemd units for `status` requests;
  required and validated before transfer.
- `--log-allowlist <file>` — allowed systemd units for `logs` requests;
  required and validated before transfer.
- `--help` — show usage.

The command requires a privileged SSH login. It uses strict host-key checking
and safely encodes provisioning payloads before sending them to the target.
The allowlists are host-level and apply to every managed account on that host.
Re-running it replaces the root-owned host allowlists, so review changes before
updating an account. Existing managed accounts keep their currently installed
helper until `create` is run again with both allowlist files.

The target account is recorded under `/etc/homelab-agent-access/accounts/`
with its username, UID, and canonical `/home/USER` path. Existing accounts are
refused unless that metadata matches passwd state. The command preflights the
managed key and sudoers content before replacing global files, uses same-directory
atomic file replacements, and restores prior files if installation fails.
Re-running the command rotates the managed key and updates the helper files.

## Audit

```bash
./bin/list root@server
./bin/list root@server --brief
./bin/list root@server --json
```

`--json` requires `jq` on the target. The audit validates account metadata,
home ownership/mode, password disabling, the managed authorized-key block, exact
sudoers content, allowlist syntax, and expected root ownership/modes. States
are `valid`, `missing`, `invalid`, `unsafe`, `legacy`, or `stale` as applicable.
Dispatcher fields report `secure`
when ownership and mode are correct; they do not attest template content. The
audit does not print allowlist contents.

## Remove

```bash
./bin/remove root@server agent
./bin/remove root@server agent --keep-home
```

Removal deletes the managed key block, the per-account sudoers rule, the
account marker, and the account. It does not delete the host-level allowlists;
those remain for other managed accounts and must be reviewed separately.
`--keep-home` preserves the home directory. Unmanaged accounts are never
removed.

## Installed remote interface

The authorized key invokes the root-owned dispatcher instead of an interactive
shell. The only accepted request forms are:

```text
status UNIT
logs UNIT LINES
ports
hardware
```

The root helper validates unit names, checks the per-host status/log
allowlists, and limits log requests to 500 lines. `ports` and `hardware` remain
available independently. It uses fixed absolute command paths and does not
interpret arbitrary shell input.

The generated key uses OpenSSH's `restrict` option plus explicit restrictions
for port forwarding, X11 forwarding, agent forwarding, PTY allocation, and
per-user SSH rc files. The generated sudoers rule permits only the root helper
with no command-line arguments. Managed metadata, keys, and allowlists are
root-only readable.

## Target requirements

The target must provide:

- OpenSSH 7.2 or newer for the authorized-key `restrict` option.
- Bash, `useradd`, `usermod`, `getent`, `install`, and `base64`.
- `sudo` at `/usr/bin/sudo` and `visudo`.
- A privileged SSH login for provisioning.

`systemctl`, `journalctl`, `ss`, `lscpu`, `lsblk`, `free`, and `sensors` are
used only when available. Missing inspection tools produce a clear error or
partial hardware output.

## Migration and limitations

Accounts created by older versions that lack a versioned management marker are
intentionally refused. Version-2 accounts with the standard `/home/USER` path
can be migrated by rerunning `create` with reviewed status and log allowlists;
nonstandard homes require manual review. `remove` refuses legacy metadata until
that migration is complete.

The forced command is a narrow interface, but it is not a complete OS sandbox.
Logs may expose secrets, and a compromised agent key can query all operations
available on that host. See [`SECURITY.md`](../SECURITY.md).
