#!/usr/bin/env bash
set -euo pipefail

# Disposable Linux integration test. CI installs the required packages before
# invoking this script. It makes real account and /etc changes and therefore
# refuses to run when existing homelab-agent-access state is present.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_USER="haa_test_$$"
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
    [[ "$pid" =~ ^[0-9]+$ ]] && sudo kill "$pid" 2>/dev/null || true
  fi

  if [[ "$SYSTEM_CLEANUP" == true ]]; then
    if id "$TEST_USER" >/dev/null 2>&1; then
      sudo userdel --remove "$TEST_USER" >/dev/null 2>&1 || true
    fi
    sudo rm -f "/etc/sudoers.d/homelab-agent-$TEST_USER"
    sudo rm -f "/etc/homelab-agent-access/accounts/$TEST_USER"
    sudo rm -f "/etc/homelab-agent-access/$TEST_USER"
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
  "/etc/sudoers.d/homelab-agent-$TEST_USER"; do
  if sudo test -e "$path" || sudo test -L "$path"; then
    echo "refusing integration test: managed path already exists: $path" >&2
    exit 73
  fi
done
if id "$TEST_USER" >/dev/null 2>&1; then
  echo "refusing integration test: account already exists: $TEST_USER" >&2
  exit 73
fi
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
AllowUsers root $TEST_USER

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
"$ROOT_DIR/bin/create" root@admin-target "$AGENT_KEY.pub" --user "$TEST_USER" \
  --status-allowlist "$STATUS_ALLOWLIST" \
  --log-allowlist "$LOG_ALLOWLIST"

ssh -o BatchMode=yes -o RequestTTY=no agent-target ports >/dev/null
ssh -o BatchMode=yes -o RequestTTY=no agent-target hardware >/dev/null
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
    .home_security == "secure" and .password == "locked" and
    .authorized_key == "valid" and .sudoers == "valid" and
    .status_allowlist == "valid" and .log_allowlist == "valid" and
    .dispatcher == "secure" and .root_helper == "secure")' >/dev/null
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  chmod 444 /etc/homelab-agent-access/status-allowlist
"$ROOT_DIR/bin/list" root@admin-target --json | \
  jq -e --arg user "$TEST_USER" '.[] | select(.user == $user and
    .status_allowlist == "unsafe")' >/dev/null
expect_agent_rc 69 'status ssh.service'
ssh -o BatchMode=yes -o RequestTTY=no admin-target \
  chmod 400 /etc/homelab-agent-access/status-allowlist

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
sed -i "s#IdentityFile .*agent-key$#IdentityFile $AGENT_KEY_2#" "$SSH_DIR/config"
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
if ssh -o BatchMode=yes -o RequestTTY=no agent-target ports >/dev/null 2>&1; then
  echo 'removed account still accepted SSH access' >&2
  exit 1
fi

printf '%s\n' 'Disposable Linux integration test passed.'
