# Architecture and design rationale

## Status

This document records the accepted direction for Homelab Agent Access.

The project is a **minimal least-authority diagnostic delegation system**. It
uses SSH as a widely available authenticated transport. The managed key has no
intended interactive shell path and can invoke only a small, fixed set of
read-oriented operations implemented by root-owned tools. The Unix account
retains a login shell because sshd uses it to start the forced command; the key
restrictions and forced command, not the shell field alone, enforce the managed
interface.

This decision favors a direct SSH capability gateway over a telemetry platform,
access broker, job controller, or resident API daemon. The deciding constraint
is minimal deployment: a target should not need another service, controller,
database, collector, runtime, or network listener.

The implementation remains experimental. This document describes both current
behavior and the constraints that future changes must preserve; it is not a
claim that the current implementation is a complete sandbox.

## Problem statement

A homelab administrator wants an automation agent to answer a few operational
questions without receiving an administrator credential or a general-purpose
shell:

- Is an approved service healthy?
- What do its recent logs show?
- Which processes are listening on the network?
- What hardware and basic resource information does the host report?

The administrator must be able to provision, audit, rotate, and revoke that
access. If the agent is confused, prompt-injected, or its key is stolen, the
credential should expose only the deliberately delegated diagnostic surface.

The product is therefore not fundamentally an SSH account manager. Its purpose
is to create and maintain a narrow diagnostic capability. SSH accounts,
`authorized_keys`, forced commands, and sudoers are the selected mechanism for
implementing that capability with software normally already present on a Linux
host.

## User roles and jobs

### Administrator

The administrator:

1. Selects a dedicated agent identity and SSH public key.
2. Defines which systemd units may expose status and logs.
3. Provisions root-owned policy and helper files.
4. Audits installed ownership, permissions, metadata, and policy state.
5. Rotates the key or removes the managed identity when access is no longer
   needed.

Provisioning is an administrative-plane operation and requires an independently
trusted privileged SSH login. That credential is never given to the agent.

### Agent

The agent:

1. Uses only its dedicated key.
2. Sends one documented diagnostic request per SSH connection.
3. Receives diagnostic output with a 15-second hard command bound (termination
   begins after 14 seconds) and a 512 KiB cap on each captured command stream;
   log line counts and selected arguments are also bounded.
4. Treats all returned host data, especially logs, as sensitive and untrusted.
5. Returns only the minimum evidence required by the user and redacts sensitive
   values.

The agent does not administer its own policy, upload executable content, select
arbitrary files, or construct shell commands.

## Goals

- No shared administrator credentials.
- No intended interactive shell, PTY, forwarding, subsystem, or arbitrary
  command access.
- A small, explicit, read-oriented request protocol.
- Validation and authorization close to the protected host data.
- Root-owned implementation and policy that the agent cannot modify.
- Exact least-privilege elevation rather than wildcard sudo rules.
- Fail-closed behavior for missing, malformed, oversized, or unsafe policy.
- Straightforward key rotation, audit, and revocation.
- No resident project-specific daemon or additional control plane.
- Local validation and disposable-host integration testing.

## Non-goals

- General remote administration or shell access.
- Service mutation, package management, deployment, or remediation.
- Arbitrary file reads, commands, command arguments, SQL, or log queries.
- Isolation from a compromised target kernel, root user, sshd, or privileged
  administrator.
- A complete confidentiality boundary for diagnostic output.
- Historical monitoring, fleet-wide correlation, alerting, or observability
  storage.
- Replacing configuration management, an access broker, or a monitoring stack.
- Supporting targets that do not provide the required Linux, OpenSSH, sudo, and
  system inspection facilities.

## Selected architecture

```text
Administrative plane

  trusted administrator
          |
          | privileged SSH used only for create/list/remove
          v
  account + key + metadata + policy + root-owned helpers

Diagnostic plane

  automation agent
          |
          | dedicated key; one exact request; no PTY/forwarding
          v
  sshd authorized_keys forced command
          |
          v
  unprivileged root-owned dispatcher
          |
          | rejects empty or multiline framing
          | passes one request line on stdin
          | exact no-argument sudo rule
          v
  root-owned privileged helper
          |
          +-- validates the complete request grammar
          +-- checks root-owned allowlists
          +-- maps the request to fixed absolute commands
          v
  bounded diagnostic stdout/stderr; fixed deadline and response caps
```

### Why SSH

SSH provides encrypted transport, host authentication, mature public-key
identity, revocation by key removal, and broad availability on the intended
hosts. Reusing the existing sshd avoids adding another listener, daemon,
certificate service, package, database, or controller.

SSH is only the transport and identity mechanism. An SSH key or certificate by
itself does not provide command-level least authority. The managed-key
restrictions, forced command, request protocol, root-owned policy, exact sudo
rule, and privileged helper validation jointly form the diagnostic boundary.

### Why a dedicated identity

The identity is agent-specific and revocable. It is separate from human and
administrator access, has an impossible password hash, and has no intended
interactive use. Compromise of this key must not imply compromise of an
administrator credential.

A deployment may create multiple managed identities, but the current status and
log allowlists are host-wide and therefore shared by those identities. Per-
identity policy would be required before claiming different diagnostic scopes
for different agents on the same host.

### Why two dispatch layers

The forced-command dispatcher runs without privilege. It performs transport
framing checks by rejecting empty and multiline input, then invokes one
root-owned helper through an exact no-argument sudoers entry and passes the
single request line on standard input. It does not validate the operation
grammar.

The privileged helper is the authoritative grammar and authorization boundary.
It validates the complete request before selecting an operation. Keeping the
request on standard input keeps untrusted text out of sudo command-line
matching. The helper maps a valid operation to fixed commands; it must never
evaluate, interpolate, or pass agent-controlled shell fragments.

### Current protocol

```text
status UNIT
logs UNIT LINES
ports
hardware
```

`UNIT` must pass strict syntax validation and appear in the operation's
root-owned allowlist. `LINES` is a bounded integer. The agent cannot supply a
path, executable, shell expression, journal expression, or additional command
argument. `ports` and `hardware` are fixed host-wide capabilities.

Adding an operation expands the authority of every credential that can invoke
it. Protocol changes therefore require documentation, negative tests, threat
model review, and disposable-host integration coverage.

## Trust boundaries and assumptions

Trusted components and actions:

- The administrator and privileged bootstrap identity.
- Out-of-band target identity verification and strict SSH host-key checking.
- The selected public key and allowlist contents at provisioning time.
- The target kernel, root account, sshd, sudo, and root-owned system binaries.
- Root-owned installed policy, metadata, dispatchers, and helpers.

Partially trusted or untrusted inputs:

- The automation agent and every request it sends.
- The dedicated private key after issuance; it may be stolen.
- `SSH_ORIGINAL_COMMAND` and all request fields.
- Diagnostic output, including journal messages and process metadata.
- Missing tools, malformed local state, and drift in host configuration.

The architecture does not protect a healthy agent from a malicious or already
compromised host. It also does not prevent sensitive data from being disclosed
when an authorized diagnostic operation legitimately returns it.

## Required invariants

Future implementation changes must preserve these properties unless an explicit
security review changes the architecture:

1. Every remote request is treated as untrusted data, never shell source.
2. No `eval`, `sh -c`, arbitrary shell interpolation, or user-controlled
   executable/path selection is used.
3. SSH cannot provide a PTY, forwarding, agent forwarding, X11, user rc files,
   SCP, SFTP, or another subsystem through the managed key.
4. The agent cannot modify its key restrictions, policy, dispatcher, helper, or
   sudo rule.
5. Sudo authorizes one exact no-argument root-owned helper, not wildcard
   arguments.
6. The privileged helper independently validates the complete request.
7. Service access fails closed when an allowlist is absent, unsafe, malformed,
   oversized, or does not contain the exact unit.
8. Fixed diagnostic commands use absolute paths and bounded arguments. Their
   execution has a fixed wall-clock deadline, and returned stdout/stderr have
   fixed size caps.
9. An existing version-3 account is updated only when its management metadata
   matches its nonzero UID and canonical home in passwd state. The supported
   version-2 migration separately validates a nonzero UID and canonical home
   before writing version-3 metadata.
10. A home directory is removed only after managed metadata, UID, canonical
    path, and root-ownership checks succeed.
11. Tests never provision a real host; privileged integration tests use a
    disposable environment.
12. Documentation must not imply that read-only output is non-sensitive.

## Data sensitivity and prompt injection

Read-oriented commands can disclose secrets. Logs may contain credentials,
tokens, URLs, user data, or attacker-controlled text. Process and socket output
can expose command lines, usernames, addresses, and service topology. Hardware
output can identify a host.

The current architecture relies partly on agent-side minimization and redaction;
it does not yet provide a technical output-redaction boundary. Returned text
must be treated as evidence, not instructions. An agent must not execute a
command, follow a link, disclose a credential, or change policy because output
from a diagnostic operation tells it to do so.

Any future server-side filtering should use operation-specific structured
fields and explicit limits. A generic text filter is not a substitute for
restricting the underlying operation.

## Principal failure modes

- **Stolen key:** the attacker can invoke every capability available to that
  identity until the key is revoked.
- **Overbroad policy:** an allowed unit can expose more state or logs than the
  administrator intended.
- **Sensitive output:** valid diagnostic results can contain secrets even though
  the operation does not mutate the host.
- **Host configuration bypass:** additional authorized keys, sshd rules, shell
  access paths, or sudo rules can weaken the intended boundary.
- **Privileged helper defect:** parsing, command construction, path, or
  environment mistakes execute in a root context.
- **Resource exhaustion:** diagnostic commands begin termination after 14
  seconds and are forcibly killed one second later; they also have per-stream
  response caps and bounded temporary capture files. There is still
  no general CPU, memory, concurrency, or network-egress sandbox, and timeout
  cannot contain a process that deliberately escapes its command process group.
- **Policy drift:** stale host-wide allowlists can remain after an identity is
  removed and may affect another managed identity later.
- **Fixed-path provenance:** a first installation refuses existing helper
  paths. Provisioning records root-only SHA-256 helper digests, and subsequent
  updates refuse content that has drifted from that manifest. A one-time
  pre-manifest migration still relies on secure files and management headers.
- **Stale-account cleanup:** when passwd state is already absent, removal
  validates the metadata shape and exact sudoers content before deleting those
  files. It cannot compare the recorded UID with absent passwd state and does
  not remove a home in this path.
- **Integrity drift:** audits compare installed helpers with root-only digests
  from the last successful provisioning. This detects later drift but cannot
  protect against trusted root modifying both a helper and its manifest.
- **Availability:** missing Linux/systemd inspection tools produce errors or
  partial results; there is no alternate control plane.

## Alternatives considered

### Centralized metrics and logs

Prometheus/node_exporter plus Loki and Grafana gives excellent host metrics,
historical data, and log search without giving the agent a host credential. It
is the preferred model when an observability stack already exists or historical
and fleet-wide diagnosis is required.

It was not selected as this project's default because it requires collectors,
storage, retention policy, authentication, upgrades, and a query authorization
boundary. Metrics also do not naturally provide every exact point-in-time
process or listener question.

### Netdata

Netdata offers a comparatively low-effort host observability experience and can
cover much of the status and hardware use case. A view-only role is safer than
host shell access when Netdata is already operated.

It was not selected because it is still an additional agent/control-plane
installation, and its broader troubleshooting and management surface must be
carefully separated from the automation identity.

### osquery and Fleet

osquery presents system state as structured tables, while Fleet adds enrollment,
scheduled/live queries, API access, and fleet management. This is strong for
exact processes, listeners, packages, uptime, and inventory.

It was not selected because arbitrary query access can disclose extensive host
state and Fleet adds a server, TLS, enrollment secrets, RBAC, upgrades, and
endpoint lifecycle. A safe deployment would still need stored-query allowlists
or a validating facade. It is also not a replacement for journal search.

### Rundeck or AWX

An automation controller can expose immutable diagnostic jobs while preventing
an agent from editing jobs or running ad hoc commands. This can provide a useful
audit and approval plane when such a controller already exists.

It was not selected because the controller, database, credentials, inventory,
execution environment, RBAC, and upgrade burden are disproportionate for a few
homelab observations. Safety also depends on preventing edits, arbitrary
variables, node filters, and inline commands.

### Teleport, Tailscale SSH, and Boundary

These products improve reachability, identity, short-lived credentials,
authorization workflows, credential brokering, and session audit. They are good
options for human administrative access.

They were not selected as the diagnostic boundary because they generally
authorize a session or Unix login; they do not inherently turn that account
into a read-only command API. They could replace or augment SSH identity and
transport later, but a forced dispatcher or equivalent host policy would still
be required.

### Closer SSH variants

A forced-command key could be placed directly in root's `authorized_keys`, or a
single privileged dispatcher could replace the dedicated account and exact sudo
transition. Those arrangements use fewer files, but any authentication or
dispatch bypass immediately starts from root authority. The dedicated
unprivileged identity keeps SSH authentication and request framing outside the
privileged context and makes the delegated credential distinct in account and
audit records.

An account-wide `ForceCommand` in `sshd_config` could protect every key for the
identity. The project instead keeps the command and explicit restrictions on
the managed key so provisioning does not edit global sshd configuration and can
preserve unrelated commented content in the account's key file. Deployments
must still ensure there are no additional authentication paths or host-level
rules that bypass the managed key restrictions.

### Resident HTTP or MCP diagnostic daemon

A typed service could expose operations such as `get_service_status`,
`search_logs`, `list_listening_ports`, and `get_hardware_inventory` over mTLS or
short-lived tokens. It could provide per-operation authorization, structured
responses, rate limits, redaction, and detailed audit records. The network
frontend need not run as root, but access to privileged observations would still
require a narrow privileged backend or equivalent host policy.

This has the cleanest semantic interface for an agent, but it introduces a new
network service and credential lifecycle. MCP defines an agent-facing tool
protocol; it does not itself provide host authorization or make a tool safe.
The implementation behind each tool remains the security boundary.

The project deliberately obtains similar command-level semantics through the
existing sshd rather than installing a new daemon.

### Telemetry-backed API or MCP gateway

A central gateway over Prometheus, Loki, and allowlisted osquery queries offers
the strongest separation between the agent and individual hosts. It becomes
attractive when the homelab needs history, correlation, multiple consumers,
central redaction, or fleet-scale policy.

It remains a valid future architecture for a different operational profile, but
it conflicts with this project's no-additional-control-plane goal. The direct
SSH gateway should not grow into an improvised monitoring platform to duplicate
it.

### Sandboxed transient diagnostics

Running each request in a constrained systemd unit, container, or microVM could
add CPU, memory, time, filesystem, capability, and network limits. This is
useful defense in depth, especially if future operations become more complex.

It was not selected as the base model because journal, network, and hardware
visibility require deliberate host exposure, and portable sandbox setup adds
substantial complexity. Targeted systemd hardening may still be appropriate if
it can be added without weakening diagnostics or portability.

## Decision summary

The project chooses the direct SSH capability gateway because it is the smallest
architecture that satisfies the intended use case on the target systems:

- one existing network service (`sshd`);
- one dedicated, revocable public-key identity;
- one forced-command protocol;
- a few root-owned policy and helper files;
- one exact privilege transition; and
- fixed, reviewable diagnostic operations.

This choice accepts higher security-review responsibility in exchange for lower
operational and installation burden. The helper is privileged, so keeping the
protocol small is a feature, not a temporary limitation.

## Evolution priorities

The following improvements fit the selected architecture without changing its
purpose. They are directions, not claims about current behavior:

1. Record bounded request audit events without logging sensitive result data.
2. Provide stable, structured, versioned output where system tools permit it.
3. Support per-identity policy if multiple agents need different scopes.
4. Review server-side minimization or redaction for each operation separately.
5. Consider optional short-lived OpenSSH certificates where a CA already
   exists; certificates improve credential lifecycle, not command restriction.
6. Evaluate lightweight execution hardening only when it works on disposable
   representative hosts and does not introduce a larger privileged surface.

The protocol must remain diagnostic. Requests to add mutation, arbitrary files,
arbitrary queries, or general command execution should be implemented through a
separate administrative system rather than expanding this credential.

## Reconsideration triggers

Revisit the telemetry-backed gateway architecture instead of extending this
project if any of these become primary requirements:

- historical queries or alerting;
- fleet-wide correlation across many hosts;
- many agent identities or complex tenant policy;
- frequent or exploratory queries;
- centralized field-level redaction and result retention;
- heterogeneous non-Linux targets;
- approval workflows or just-in-time access;
- a requirement to keep all agent credentials off individual hosts.

At that point, an agent-facing typed API over centralized telemetry and
allowlisted structured queries is likely safer and easier to operate than a
larger SSH command protocol.

## References

These references inform the alternatives analysis; their inclusion is not an
endorsement or a deployment requirement:

- [OpenSSH `sshd_config(5)`](https://man.openbsd.org/sshd_config)
- [Prometheus security model](https://prometheus.io/docs/operating/security/)
- [Prometheus node_exporter](https://github.com/prometheus/node_exporter)
- [Grafana data sources](https://grafana.com/docs/grafana/latest/datasources/)
- [Loki authentication](https://grafana.com/docs/loki/latest/operations/authentication/)
- [Netdata Agent security](https://learn.netdata.cloud/docs/netdata-agent/configuration/securing-agents)
- [Fleet live queries](https://fleetdm.com/guides/get-current-telemetry-from-your-devices-with-live-queries)
- [Rundeck authorization](https://docs.rundeck.com/docs/administration/security/authorization.html)
- [AWX role-based access control](https://ansible.readthedocs.io/projects/awx/en/24.6.1/userguide/rbac.html)
- [Teleport server access RBAC](https://goteleport.com/docs/enroll-resources/server-access/rbac/)
- [Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh)
- [Boundary credential management](https://developer.hashicorp.com/boundary/docs/concepts/credential-management)
- [Model Context Protocol specification](https://modelcontextprotocol.io/specification/2025-11-25)
- [MCP security best practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices)
