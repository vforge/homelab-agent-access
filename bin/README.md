# Administrator command reference

These commands provision and audit the agent account. They are for a trusted
administrator, not for the agent using the resulting account.

> **Security warning:** This is experimental homelab tooling. Test on a
disposable target, read [`SECURITY.md`](../SECURITY.md), and verify the remote
host key before provisioning.

## Create or update

Copy the separate [status](../examples/status-allowlist.example) and
[log](../examples/log-allowlist.example) templates outside this repository.
They contain only comments and initially deny both operations; uncomment only
units reviewed for that operation. Logs may contain secrets even when status is
safe. Blank lines and lines beginning with `#` are ignored; an empty file
denies that operation. Each file is limited to 65,536 bytes and 1,024 units.

```bash
cp examples/status-allowlist.example /path/to/status-units.txt
cp examples/log-allowlist.example /path/to/log-units.txt
./bin/create root@server ~/.ssh/agent.pub --user agent \
  --status-allowlist /path/to/status-units.txt \
  --log-allowlist /path/to/log-units.txt
```

Options:

- `--sudo` — run as an SSH key-authenticated admin with sudo; prompts on a TTY.
- `--user <name>` — remote account name. If omitted, it is derived from the
  public-key filename.
- `--status-allowlist <file>` — allowed systemd units for `status` requests;
  required and validated before transfer.
- `--log-allowlist <file>` — allowed systemd units for `logs` requests;
  required and validated before transfer.
- `--help` — show usage.

The command requires a privileged SSH login. With a key-authenticated admin
login that has password-protected sudo, add `--sudo` and run from an interactive
terminal; the password is entered at sudo's remote TTY prompt, never in a CLI
argument or the script stream. Use `--sudo` for `list` and `remove` too. This
mode requires the admin to be authorized to run `/bin/bash` as root and is
therefore an administrative root-equivalent permission. The agent account does
not need to exist before `create`; the command creates it. Both transports use
strict host-key checking and encode provisioning payloads before transfer.
The allowlists are host-level and apply to every managed account on that host.
Edits to local copies do not apply automatically. To change policy for an
existing account, rerun `create` with the same public key and account name and
pass both current allowlist files, even if only one changed; add `--sudo` when
using a sudo administrator. Re-running it replaces both root-owned host
allowlists for every managed account, so review newly allowed units (especially
logs) before updating. The same public key retains the managed key; a different
one rotates it.

The target account is recorded under `/etc/homelab-agent-access/accounts/`
with its username, UID, and canonical `/home/USER` path. Existing accounts are
refused unless that metadata matches passwd state, and a new account is refused
if its expected home already exists. A first installation refuses pre-existing
fixed helper paths. Provisioning records root-only SHA-256 digests for both
helpers. Updates require those helpers to match their recorded digests, plus
valid existing allowlists and exact managed sudoers/metadata content, before
replacement. The command uses same-directory atomic file replacements and
restores prior files if installation fails.
Re-running the command rotates the managed key and updates the helper files.

## Audit

```bash
./bin/list root@server
./bin/list root@server --brief
./bin/list root@server --json
```

`--json` requires `jq` on the target. `--sudo` works with all output formats;
its result stream is kept separate from the terminal's sudo prompt. The audit
validates account metadata, home ownership/mode, password disabling, the managed authorized-key block, exact
sudoers content, allowlist syntax, expected root ownership/modes, the helper
digest manifest, and installed helper SHA-256 values. States include `valid`,
`missing`, `invalid`, `unsafe`, `legacy`, `stale`, and `unattested` as
applicable. Dispatcher fields report `secure` only when ownership, mode, and the
recorded digest match. The audit does not print allowlist contents.

## Remove

```bash
./bin/remove root@server agent
./bin/remove root@server agent --keep-home
```

`--sudo` also applies to removal when using an admin account. Removal deletes
the managed key block, the per-account sudoers rule, the account marker, and
the account. It does not delete the host-level allowlists;
those remain for other managed accounts and must be reviewed separately.
`--keep-home` preserves the home directory. Unmanaged accounts are never
removed. If passwd state is already absent, removal validates the residual
metadata shape and exact sudoers content before deleting those two files; it
never removes a home in that stale-state path.

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

Each diagnostic command begins termination after 14 seconds and is forcibly
killed one second later if needed. Captured stdout and stderr are each limited
to 512 KiB and are emitted after the command finishes. A timeout returns status
124, even if output was also truncated; truncation alone returns status 75.
Either response may contain partial diagnostic output and must not be treated as
a successful, complete result.

The generated key uses OpenSSH's `restrict` option plus explicit restrictions
for port forwarding, X11 forwarding, agent forwarding, PTY allocation, and
per-user SSH rc files. The generated sudoers rule permits only the root helper
with no command-line arguments. Managed metadata and allowlists are root-only
readable. The public authorized-key file is root-owned and read-only while
remaining readable to sshd's unprivileged account lookup.

## Target requirements

The target must provide:

- OpenSSH 7.2 or newer for the authorized-key `restrict` option.
- Bash, `useradd`, `usermod`, `getent`, `install`, `base64`, `cmp`, `head`,
  `timeout`, and `sha256sum`.
- `sudo` at `/usr/bin/sudo` and `visudo`.
- A privileged SSH login for provisioning, or a key-authenticated administrator
  login with sudo permission to run `/bin/bash` and an interactive terminal.

`systemctl`, `journalctl`, `ss`, `lscpu`, `lsblk`, `free`, and `sensors` are
used only when available. Missing inspection tools produce a clear error or
partial hardware output.

## Administrative sudo transport

`--sudo` stages the trusted script in a 0700 temporary directory on the target,
then starts it with `sudo /bin/bash` over an SSH TTY. Captured stdout and stderr
are fetched separately and the temporary files are removed afterward. The
administrator must trust their SSH account and the host: that account owns the
staged script and can modify it. A disconnect or interruption can leave the
staged script, public key, allowlist contents, or diagnostic audit output in the
admin-owned temporary directory; inspect and remove such directories on the
host before retrying. The code does not create an agent sudo rule with broader
permissions. Password sudo requires a real controlling terminal; noninteractive
runs fail closed. SSH itself still requires key authentication (`BatchMode=yes`).

## Migration and limitations

Accounts created by older versions that lack a versioned management marker are
intentionally refused. Version-2 accounts with the standard `/home/USER` path
can be migrated by rerunning `create` with reviewed status and log allowlists;
nonstandard homes require manual review. `remove` refuses legacy metadata until
that migration is complete. An installation created before helper digests were
introduced can migrate once when both helpers have secure ownership/modes and
recognized management headers; provisioning then replaces them and records the
new exact digests.

The forced command is a narrow interface, but it is not a complete OS sandbox.
Logs may expose secrets, and a compromised agent key can query all operations
available on that host. See [`SECURITY.md`](../SECURITY.md).
