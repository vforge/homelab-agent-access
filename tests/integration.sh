#!/usr/bin/env bash
set -euo pipefail

# Disposable Linux integration test. CI installs the required packages before
# invoking this script. It makes real account and /etc changes and therefore
# refuses to run when existing homelab-agent-access state is present.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_USER="haa_test_$$"
NAMESPACE_USER="helper-digests"
TMP_BASE="${RUNNER_TEMP:-/tmp}"
WORK_DIR=""
ADMIN_AUTH_DIR="/run/homelab-agent-access-integration-$$"
ADMIN_AUTH_KEYS="$ADMIN_AUTH_DIR/authorized_keys"
HOST_KEY_ROOT="$ADMIN_AUTH_DIR/host-key"
PID_FILE="$ADMIN_AUTH_DIR/sshd.pid"
SYSTEM_CLEANUP=false

cleanup() {
  local pid=""
  if sudo test -f "$PID_FILE" 2>/dev/null; then
    pid="$(sudo cat "$PID_FILE" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      sudo kill "$pid" 2>/dev/null || true
    fi
  fi

  if [[ "$SYSTEM_CLEANUP" == true ]]; then
    for cleanup_user in "$TEST_USER" "$NAMESPACE_USER"; do
      if id "$cleanup_user" >/dev/null 2>&1; then
        sudo userdel --remove "$cleanup_user" >/dev/null 2>&1 || true
      fi
      sudo rm -rf --one-file-system -- "/home/$cleanup_user"
      sudo rm -f "/etc/sudoers.d/homelab-agent-$cleanup_user"
      sudo rm -f "/etc/homelab-agent-access/accounts/$cleanup_user"
      sudo rm -f "/etc/homelab-agent-access/$cleanup_user"
    done
    sudo rm -f /usr/local/sbin/homelab-agent-dispatch
    sudo rm -f /usr/local/sbin/homelab-agent-dispatch-root
    sudo rm -rf /etc/homelab-agent-access
  fi

  sudo rm -rf "$ADMIN_AUTH_DIR" 2>/dev/null || true
  if [[ -n "$WORK_DIR" ]]; then
    sudo rm -rf "$WORK_DIR" 2>/dev/null || rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$(id -u)" -eq 0 ]]; then
  echo 'Run this test as a normal user with passwordless sudo.' >&2
  exit 1
fi
if ! sudo -n true 2>/dev/null; then
  echo 'passwordless sudo is required for the disposable integration test' >&2
  exit 69
fi

for required in ssh ssh-keygen ssh-keyscan sudo python3 jq; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "missing local test command: $required" >&2
    exit 69
  }
done
REAL_SSH="$(command -v ssh)"
for required in /usr/sbin/sshd /usr/sbin/visudo; do
  [[ -x "$required" ]] || {
    echo "missing local test command: $required" >&2
    exit 69
  }
done

# Never overwrite a real installation. The test owns these global paths only
# after this preflight succeeds.
for path in \
  /etc/homelab-agent-access \
  /usr/local/sbin/homelab-agent-dispatch \
  /usr/local/sbin/homelab-agent-dispatch-root \
  "/etc/sudoers.d/homelab-agent-$TEST_USER" \
  "/etc/sudoers.d/homelab-agent-$NAMESPACE_USER"; do
  if sudo test -e "$path" || sudo test -L "$path"; then
    echo "refusing integration test: managed path already exists: $path" >&2
    exit 73
  fi
done
for test_account in "$TEST_USER" "$NAMESPACE_USER"; do
  if id "$test_account" >/dev/null 2>&1 || sudo test -e "/home/$test_account" || \
     sudo test -L "/home/$test_account"; then
    echo "refusing integration test: account or home already exists: $test_account" >&2
    exit 73
  fi
done
SYSTEM_CLEANUP=true

mkdir -p "$TMP_BASE"
WORK_DIR="$(mktemp -d "$TMP_BASE/homelab-agent-access-integration.XXXXXX")"
SSH_HOME="$WORK_DIR/home"
SSH_DIR="$SSH_HOME/.ssh"
SSHD_CONFIG="$WORK_DIR/sshd_config"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
ADMIN_KEY="$WORK_DIR/admin-key"
AGENT_KEY="$WORK_DIR/agent-key"
AGENT_KEY_2="$WORK_DIR/agent-key-2"
HOST_KEY="$WORK_DIR/host-key"
STATUS_ALLOWLIST="$WORK_DIR/status-allowlist"
LOG_ALLOWLIST="$WORK_DIR/log-allowlist"
CHANGED_ALLOWLIST="$WORK_DIR/changed-allowlist"
PORT="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
ssh-keygen -q -t ed25519 -N '' -f "$ADMIN_KEY"
ssh-keygen -q -t ed25519 -N '' -f "$AGENT_KEY"
ssh-keygen -q -t ed25519 -N '' -f "$AGENT_KEY_2"
ssh-keygen -q -t ed25519 -N '' -f "$HOST_KEY"
printf '%s\n' 'ssh.service' > "$STATUS_ALLOWLIST"
printf '%s\n' 'ssh.service' > "$LOG_ALLOWLIST"
printf '%s\n' 'changed.service' > "$CHANGED_ALLOWLIST"

sudo install -d -o root -g root -m 755 /run/sshd
sudo rm -rf "$ADMIN_AUTH_DIR"
sudo install -d -o root -g root -m 755 "$ADMIN_AUTH_DIR"
sudo install -o root -g root -m 600 "$HOST_KEY" "$HOST_KEY_ROOT"
sudo install -o root -g root -m 600 "$ADMIN_KEY.pub" "$ADMIN_AUTH_KEYS"

cat > "$SSHD_CONFIG" <<EOF
Port $PORT
ListenAddress 127.0.0.1
PidFile $PID_FILE
HostKey $HOST_KEY_ROOT
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
LogLevel ERROR
AllowUsers root $TEST_USER $NAMESPACE_USER

Match User root
  AuthorizedKeysFile $ADMIN_AUTH_KEYS
EOF

sudo /usr/sbin/sshd -t -f "$SSHD_CONFIG"
sudo /usr/sbin/sshd -f "$SSHD_CONFIG"

for _ in {1..20}; do
  if ssh-keyscan -p "$PORT" -T 2 127.0.0.1 > "$KNOWN_HOSTS" 2>/dev/null; then
    break
  fi
  sleep 1
done
[[ -s "$KNOWN_HOSTS" ]] || { echo 'sshd did not become ready' >&2; exit 1; }
chmod 600 "$KNOWN_HOSTS"

cat > "$SSH_DIR/config" <<EOF
Host admin-target
  HostName 127.0.0.1
  Port $PORT
  User root
  IdentityFile $ADMIN_KEY
  IdentitiesOnly yes
  UserKnownHostsFile $KNOWN_HOSTS
  StrictHostKeyChecking yes

Host agent-target
  HostName 127.0.0.1
  Port $PORT
  User $TEST_USER
  IdentityFile $AGENT_KEY
  IdentitiesOnly yes
  UserKnownHostsFile $KNOWN_HOSTS
  StrictHostKeyChecking yes
EOF
chmod 600 "$SSH_DIR/config"
export HOME="$SSH_HOME"
export HAA_TEST_REAL_SSH="$REAL_SSH"
export HAA_TEST_SSH_CONFIG="$SSH_DIR/config"
mkdir -p "$WORK_DIR/bin"
cat > "$WORK_DIR/bin/ssh" <<'SSH_WRAPPER'
#!/usr/bin/env bash
exec "${HAA_TEST_REAL_SSH:?}" -F "${HAA_TEST_SSH_CONFIG:?}" "$@"
SSH_WRAPPER
chmod 755 "$WORK_DIR/bin/ssh"
PATH="$WORK_DIR/bin:$PATH"
export PATH

# Exercise response and wall-clock bounds with a disposable helper copy and a
# fixed fake socket-inspection command. No system command is replaced.
FAKE_SS="$WORK_DIR/fake-ss"
BOUNDED_HELPER="$WORK_DIR/bounded-helper"
cat > "$FAKE_SS" <<'FAKE_OUTPUT'
#!/bin/bash
/usr/bin/python3 - <<'PY'
import sys
sys.stdout.write("o" * 600000)
sys.stderr.write("e" * 600000)
PY
FAKE_OUTPUT
chmod 755 "$FAKE_SS"
sed -e "s#/usr/bin/ss#$FAKE_SS#g" \
  -e "s#/bin/ss#$FAKE_SS#g" \
  "$ROOT_DIR/remote/homelab-agent-dispatch-root" > "$BOUNDED_HELPER"
chmod 755 "$BOUNDED_HELPER"
set +e
printf '%s\n' ports | bash "$BOUNDED_HELPER" \
  > "$WORK_DIR/bounded.stdout" 2> "$WORK_DIR/bounded.stderr"
bounded_rc=$?
set -e
[[ "$bounded_rc" -eq 75 ]]
/usr/bin/python3 - "$WORK_DIR/bounded.stdout" "$WORK_DIR/bounded.stderr" <<'PY'
from pathlib import Path
import sys
stdout = Path(sys.argv[1]).read_bytes()
stderr = Path(sys.argv[2]).read_bytes()
assert stdout == b"o" * 524288
assert stderr == (
    b"e" * 524288
    + b"Diagnostic output exceeded the 512 KiB per-stream limit\n"
)
PY

# The capture-file ulimit must stop output well before an unbounded producer can
# fill the filesystem; the returned stream remains capped. A SIGXFSZ handler
# records that the producer hit the kernel limit, so this does not merely test
# response truncation.
export HAA_FILE_LIMIT_MARKER="$WORK_DIR/file-limit.marker"
cat > "$FAKE_SS" <<'FAKE_FILE_LIMIT'
#!/bin/bash
/usr/bin/python3 - <<'PY'
import os
from pathlib import Path
import signal

marker = Path(os.environ["HAA_FILE_LIMIT_MARKER"])

def limited(_signum, _frame):
    marker.write_text("SIGXFSZ\n", encoding="ascii")
    os._exit(99)

signal.signal(signal.SIGXFSZ, limited)
chunk = b"x" * 65536
written = 0
while written < 3000000:
    written += os.write(1, chunk)
PY
FAKE_FILE_LIMIT
chmod 755 "$FAKE_SS"
set +e
printf '%s\n' ports | bash "$BOUNDED_HELPER" \
  > "$WORK_DIR/file-limit.stdout" 2> "$WORK_DIR/file-limit.stderr"
file_limit_rc=$?
set -e
[[ "$file_limit_rc" -eq 75 ]]
[[ "$(wc -c < "$WORK_DIR/file-limit.stdout")" -eq 524288 ]]
grep -qx SIGXFSZ "$HAA_FILE_LIMIT_MARKER"
unset HAA_FILE_LIMIT_MARKER

# A TERM-ignoring command and child must be killed within the hard limit.
# Timeout takes precedence when its already-produced output is also truncated.
export HAA_TIMEOUT_PID_FILE="$WORK_DIR/timeout-child.pid"
cat > "$FAKE_SS" <<'FAKE_TIMEOUT'
#!/bin/bash
/usr/bin/python3 - <<'PY'
import sys
sys.stdout.write("t" * 600000)
PY
trap '' TERM
sleep 30 &
printf '%s\n' "$!" > "${HAA_TIMEOUT_PID_FILE:?}"
wait
FAKE_TIMEOUT
chmod 755 "$FAKE_SS"
sed -e "s#/usr/bin/ss#$FAKE_SS#g" \
  -e "s#/bin/ss#$FAKE_SS#g" \
  -e 's/COMMAND_TERM_SECONDS=14/COMMAND_TERM_SECONDS=1/' \
  -e 's/COMMAND_MAX_SECONDS=15/COMMAND_MAX_SECONDS=2/' \
  "$ROOT_DIR/remote/homelab-agent-dispatch-root" > "$BOUNDED_HELPER"
chmod 755 "$BOUNDED_HELPER"
timeout_started=$SECONDS
set +e
printf '%s\n' ports | bash "$BOUNDED_HELPER" \
  > "$WORK_DIR/timeout.stdout" 2> "$WORK_DIR/timeout.stderr"
timeout_rc=$?
set -e
timeout_elapsed=$((SECONDS - timeout_started))
[[ "$timeout_rc" -eq 124 ]]
(( timeout_elapsed >= 1 && timeout_elapsed <= 4 ))
grep -q 'output also exceeded' "$WORK_DIR/timeout.stderr"
grep -q '2-second hard limit' "$WORK_DIR/timeout.stderr"
timeout_child="$(<"$HAA_TIMEOUT_PID_FILE")"
if kill -0 "$timeout_child" 2>/dev/null; then
  kill -KILL "$timeout_child" 2>/dev/null || true
  echo 'timeout left a descendant process running' >&2
  exit 1
fi
unset HAA_TIMEOUT_PID_FILE

expect_agent_rc() {
  local expected="$1" request="$2" rc
  set +e
  ssh -o BatchMode=yes -o RequestTTY=no agent-target "$request" \
    > "$WORK_DIR/agent.stdout" 2> "$WORK_DIR/agent.stderr"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "unexpected agent exit for '$request': got $rc, expected $expected" >&2
    cat "$WORK_DIR/agent.stderr" >&2
    exit 1
  fi
}

ssh -o BatchMode=yes -o RequestTTY=no admin-target true

# A first installation must not adopt or replace a fixed helper path that has
# no corresponding managed installation state.
printf '%s\n' '#!/bin/bash' '# unrelated file' > "$WORK_DIR/unmanaged-dispatcher"
sudo install -o root -g root -m 755 "$WORK_DIR/unmanaged-dispatcher" \
  /usr/local/sbin/homelab-agent-dispatch
set +e
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST" \
  > "$WORK_DIR/collision.stdout" 2> "$WORK_DIR/collision.stderr"
collision_rc=$?
set -e
[[ "$collision_rc" -eq 73 ]]
sudo cmp "$WORK_DIR/unmanaged-dispatcher" /usr/local/sbin/homelab-agent-dispatch
if id "$TEST_USER" >/dev/null 2>&1; then
  echo 'failed provisioning left the test account behind' >&2
  exit 1
fi
sudo test ! -e /etc/homelab-agent-access
sudo rm -f /usr/local/sbin/homelab-agent-dispatch

# Failed provisioning must never adopt and later remove a pre-existing home.
sudo install -d -o root -g root -m 755 "/home/$TEST_USER"
sudo touch "/home/$TEST_USER/unmanaged-sentinel"
set +e
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST" \
  > "$WORK_DIR/home-collision.stdout" 2> "$WORK_DIR/home-collision.stderr"
home_collision_rc=$?
set -e
[[ "$home_collision_rc" -eq 73 ]]
sudo test -f "/home/$TEST_USER/unmanaged-sentinel"
sudo rm -rf --one-file-system -- "/home/$TEST_USER"

"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST"

# A pre-attestation installation with recognizable secure helpers can migrate
# once; the update must recreate the digest manifest.
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  rm /etc/homelab-agent-access/.helper-digests
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .helper_manifest == "missing" and .dispatcher == "unattested" and
    .root_helper == "unattested")' >/dev/null
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST"

# The hidden manifest namespace must not collide with a valid account name.
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY.pub" --user "$NAMESPACE_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST"
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$NAMESPACE_USER" '.[] | select(.user == $user and
    .helper_manifest == "valid" and .dispatcher == "secure" and
    .root_helper == "secure")' >/dev/null
"$ROOT_DIR/bin/remove" root@admin-target "$NAMESPACE_USER"

ssh -o BatchMode=yes -o RequestTTY=no agent-target ports >/dev/null
ssh -o BatchMode=yes -o RequestTTY=no agent-target hardware >/dev/null
if ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "sudo -u $TEST_USER sudo -n /usr/local/sbin/homelab-agent-dispatch-root --internal-hardware" \
  >/dev/null 2>&1; then
  echo 'sudoers accepted a private helper argument' >&2
  exit 1
fi
expect_agent_rc 77 'status unlisted.service'
expect_agent_rc 77 'logs unlisted.service 1'
expect_agent_rc 64 'status --bad'
expect_agent_rc 64 'logs ssh.service 501'

# An allowlisted unit must pass authorization. systemctl/journalctl may still
# fail on a CI runner without systemd, but the dispatcher must not return 77.
for request in 'status ssh.service' 'logs ssh.service 1'; do
  set +e
  ssh -o BatchMode=yes -o RequestTTY=no agent-target "$request" \
    > "$WORK_DIR/allowed.stdout" 2> "$WORK_DIR/allowed.stderr"
  rc=$?
  set -e
  if [[ "$rc" -eq 77 ]]; then
    echo "allowlisted request was denied: $request" >&2
    cat "$WORK_DIR/allowed.stderr" >&2
    exit 1
  fi
done

# Remote forwarding is requested before the valid forced command. If the key
# restriction is missing, the request succeeds and `ports` returns zero.
if ssh -o BatchMode=yes -o RequestTTY=no -o ExitOnForwardFailure=yes \
  -R 0:127.0.0.1:"$PORT" agent-target ports >/dev/null 2>&1; then
  echo 'remote port forwarding was accepted' >&2
  exit 1
fi

# Verify the managed key and audit output rather than accepting file existence.
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "grep -q 'restrict,no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty,no-user-rc' /home/$TEST_USER/.ssh/authorized_keys"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "grep -q '^version=3$' /etc/homelab-agent-access/accounts/$TEST_USER"
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .state == "present" and .metadata == "valid" and
    .home_security == "secure" and .password == "disabled" and
    .authorized_key == "valid" and .sudoers == "valid" and
    .status_allowlist == "valid" and .log_allowlist == "valid" and
    .helper_manifest == "valid" and .dispatcher == "secure" and
    .root_helper == "secure")' >/dev/null
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  chmod 444 /etc/homelab-agent-access/status-allowlist
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .status_allowlist == "unsafe")' >/dev/null
expect_agent_rc 69 'status ssh.service'
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  chmod 400 /etc/homelab-agent-access/status-allowlist

# Audits and updates must reject helper content that no longer matches the
# root-owned digest manifest.
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "printf '%s\\n' '# unexpected drift' >> /usr/local/sbin/homelab-agent-dispatch-root"
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .helper_manifest == "valid" and .root_helper == "invalid")' >/dev/null
set +e
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY_2.pub" --user "$TEST_USER" \
  --status-allowlist "$CHANGED_ALLOWLIST" \
  --log-allowlist "$CHANGED_ALLOWLIST" \
  > "$WORK_DIR/attestation.stdout" 2> "$WORK_DIR/attestation.stderr"
attestation_rc=$?
set -e
[[ "$attestation_rc" -eq 73 ]]
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "grep -qx '# unexpected drift' /usr/local/sbin/homelab-agent-dispatch-root && grep -qx 'ssh.service' /etc/homelab-agent-access/status-allowlist"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "sed -i '\$d' /usr/local/sbin/homelab-agent-dispatch-root"
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .helper_manifest == "valid" and .root_helper == "secure")' >/dev/null

ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "printf '%s\\n' 'unexpected=true' >> /etc/homelab-agent-access/.helper-digests"
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .helper_manifest == "invalid" and .dispatcher == "invalid" and
    .root_helper == "invalid")' >/dev/null
set +e
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY_2.pub" --user "$TEST_USER" \
  --status-allowlist "$CHANGED_ALLOWLIST" \
  --log-allowlist "$CHANGED_ALLOWLIST" \
  > "$WORK_DIR/manifest.stdout" 2> "$WORK_DIR/manifest.stderr"
manifest_rc=$?
set -e
[[ "$manifest_rc" -eq 73 ]]
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "sed -i '\$d' /etc/homelab-agent-access/.helper-digests"

# A preflight failure must not replace shared allowlists or other artifacts.
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "printf '%s\\n' unmanaged-entry >> /home/$TEST_USER/.ssh/authorized_keys"
set +e
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY_2.pub" --user "$TEST_USER" \
  --status-allowlist "$CHANGED_ALLOWLIST" \
  --log-allowlist "$CHANGED_ALLOWLIST" \
  > "$WORK_DIR/preflight.stdout" 2> "$WORK_DIR/preflight.stderr"
preflight_rc=$?
set -e
[[ "$preflight_rc" -eq 73 ]]
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "grep -qx 'ssh.service' /etc/homelab-agent-access/status-allowlist"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "sed -i '\$d' /home/$TEST_USER/.ssh/authorized_keys"

# Key rotation must accept the new key and reject the old key.
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY_2.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST"
sed -i "s#^  IdentityFile $AGENT_KEY\$#  IdentityFile $AGENT_KEY_2#" "$SSH_DIR/config"
ssh -o BatchMode=yes -o RequestTTY=no agent-target ports >/dev/null
if ssh -o BatchMode=yes -o RequestTTY=no \
  -o IdentitiesOnly=yes -o IdentityFile="$AGENT_KEY" \
  -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes \
  -p "$PORT" "$TEST_USER@127.0.0.1" ports >/dev/null 2>&1; then
  echo 'old agent key remained usable after rotation' >&2
  exit 1
fi

# Removal must refuse passwd state that no longer matches the recorded home.
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  usermod --home "/tmp/$TEST_USER-unsafe-home" "$TEST_USER"
set +e
"$ROOT_DIR/bin/remove" root@admin-target "$TEST_USER" \
  > "$WORK_DIR/remove.stdout" 2> "$WORK_DIR/remove.stderr"
remove_rc=$?
set -e
[[ "$remove_rc" -eq 65 ]]
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  usermod --home "/home/$TEST_USER" "$TEST_USER"

"$ROOT_DIR/bin/remove" root@admin-target "$TEST_USER"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  test ! -e "/home/$TEST_USER"
if ssh -o BatchMode=yes -o RequestTTY=no agent-target ports >/dev/null 2>&1; then
  echo 'removed account still accepted SSH access' >&2
  exit 1
fi

# If passwd state disappears before managed cleanup, removal must validate both
# residual metadata and sudoers content before deleting either file.
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY_2.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST"
ssh -o BatchMode=yes -o RequestTTY=no admin-target userdel "$TEST_USER"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "printf '%s\\n' tampered >> /etc/homelab-agent-access/accounts/$TEST_USER"
set +e
"$ROOT_DIR/bin/remove" root@admin-target "$TEST_USER" \
  > "$WORK_DIR/stale-marker.stdout" 2> "$WORK_DIR/stale-marker.stderr"
stale_marker_rc=$?
set -e
[[ "$stale_marker_rc" -eq 73 ]]
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "test -e /etc/homelab-agent-access/accounts/$TEST_USER && sed -i '\$d' /etc/homelab-agent-access/accounts/$TEST_USER"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "printf '\\n' >> /etc/sudoers.d/homelab-agent-$TEST_USER"
set +e
"$ROOT_DIR/bin/remove" root@admin-target "$TEST_USER" \
  > "$WORK_DIR/stale-sudoers.stdout" 2> "$WORK_DIR/stale-sudoers.stderr"
stale_sudoers_rc=$?
set -e
[[ "$stale_sudoers_rc" -eq 73 ]]
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "test -e /etc/sudoers.d/homelab-agent-$TEST_USER && sed -i '\$d' /etc/sudoers.d/homelab-agent-$TEST_USER"
"$ROOT_DIR/bin/remove" root@admin-target "$TEST_USER"
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  "test ! -e /etc/homelab-agent-access/accounts/$TEST_USER && test ! -e /etc/sudoers.d/homelab-agent-$TEST_USER && test -d /home/$TEST_USER"

printf '%s\n' 'Disposable Linux integration test passed.'
