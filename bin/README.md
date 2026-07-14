# Administrator command reference

These commands provision and audit the agent account. They are for a trusted
administrator, not for the agent using the resulting account.

> **Security warning:** This is experimental homelab tooling. Test on a
disposable target, read [`SECURITY.md`](../SECURITY.md), and verify the remote
host key before provisioning.

## Create or update

Create one line-delimited allowlist file for each operation outside this
repository. Blank lines and lines beginning with `#` are ignored; an empty file
denies that operation.

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

The target account is marked under `/etc/homelab-agent-access/` and is refused
if an existing account is not managed by this tool. Re-running the command
rotates the managed key and updates the helper files.

## Audit

```bash
./bin/list root@server
./bin/list root@server --brief
./bin/list root@server --json
```

`--json` requires `jq` on the target. The audit reports managed accounts,
account state, home directory, shell, managed-key presence, sudo-helper and
allowlist presence, and the exposed operation forms. It does not print the
allowlist contents.

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

The generated key disables port forwarding, X11 forwarding, agent forwarding,
PTY allocation, and per-user SSH rc files. The generated sudoers rule permits
only the root helper with no command-line arguments.

## Target requirements

The target must provide:

- Bash, `useradd`, `usermod`, `getent`, `install`, and `base64`.
- `sudo` at `/usr/bin/sudo` and `visudo`.
- A privileged SSH login for provisioning.

`systemctl`, `journalctl`, `ss`, `lscpu`, `lsblk`, `free`, and `sensors` are
used only when available. Missing inspection tools produce a clear error or
partial hardware output.

## Migration and limitations

Accounts created by older versions that lack the versioned management marker
are intentionally refused. Remove or migrate them manually after review.
Existing managed accounts are not updated automatically; rerun `create` with
reviewed status and log allowlists after upgrading the helper.

The forced command is a narrow interface, but it is not a complete OS sandbox.
Logs may expose secrets, and a compromised agent key can query all operations
available on that host. See [`SECURITY.md`](../SECURITY.md).
