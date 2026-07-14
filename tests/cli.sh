#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ssh-keygen -q -t ed25519 -N '' -f "$TMP_DIR/test-key"
printf '%s\n' "$(sed 's/ [^ ]*$/ agent test/' "$TMP_DIR/test-key.pub")" > "$TMP_DIR/test-key.pub"
printf '%s\n' '# permitted units' '' 'agent.service' > "$TMP_DIR/status-allowlist"
printf '%s\n' '# permitted units' '' 'agent.service' > "$TMP_DIR/log-allowlist"
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${FAKE_SSH_CAPTURE:?}"
FAKE_SSH
chmod +x "$TMP_DIR/bin/ssh"

"$ROOT_DIR/bin/create" --help >/dev/null 2>&1
"$ROOT_DIR/bin/list" --help >/dev/null 2>&1
"$ROOT_DIR/bin/remove" --help >/dev/null 2>&1

FAKE_SSH_CAPTURE="$TMP_DIR/ssh.args" \
PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/bin/create" root@server "$TMP_DIR/test-key.pub" --user agent \
  --status-allowlist "$TMP_DIR/status-allowlist" \
  --log-allowlist "$TMP_DIR/log-allowlist" >/dev/null

args=()
while IFS= read -r arg; do
  args+=("$arg")
done < "$TMP_DIR/ssh.args"
[[ ${#args[@]} -eq 19 ]]
[[ "${args[9]}" == root@server ]]
[[ "${args[13]}" == agent ]]
for index in 14 15 16 17 18; do
  [[ "${args[$index]}" =~ ^[A-Za-z0-9+/=]+$ ]]
done

decode_b64() {
  if printf '' | base64 -d >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d
  else
    printf '%s' "$1" | base64 -D
  fi
}
decode_b64 "${args[14]}" | grep -q 'agent test'
decode_b64 "${args[15]}" | cmp - "$ROOT_DIR/remote/homelab-agent-dispatch"
decode_b64 "${args[16]}" | cmp - "$ROOT_DIR/remote/homelab-agent-dispatch-root"
decode_b64 "${args[17]}" | cmp - "$TMP_DIR/status-allowlist"
decode_b64 "${args[18]}" | cmp - "$TMP_DIR/log-allowlist"

FAKE_SSH_CAPTURE="$TMP_DIR/ssh.args" \
PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/bin/list" root@server --json >/dev/null
args=()
while IFS= read -r arg; do
  args+=("$arg")
done < "$TMP_DIR/ssh.args"
[[ "${args[9]}" == root@server ]]
[[ "${args[13]}" == json ]]

FAKE_SSH_CAPTURE="$TMP_DIR/ssh.args" \
PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/bin/remove" root@server agent --keep-home >/dev/null
args=()
while IFS= read -r arg; do
  args+=("$arg")
done < "$TMP_DIR/ssh.args"
[[ "${args[9]}" == root@server ]]
[[ "${args[13]}" == agent ]]
[[ "${args[14]}" == true ]]

if PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/create" root@server \
  "$TMP_DIR/test-key.pub" --user 'bad;name' \
  --status-allowlist "$TMP_DIR/status-allowlist" \
  --log-allowlist "$TMP_DIR/log-allowlist" >/dev/null 2>&1; then
  echo 'invalid username was accepted' >&2
  exit 1
fi
printf '%s\n' 'bad unit name' > "$TMP_DIR/invalid-allowlist"
if PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/create" root@server \
  "$TMP_DIR/test-key.pub" --user agent \
  --status-allowlist "$TMP_DIR/invalid-allowlist" \
  --log-allowlist "$TMP_DIR/log-allowlist" >/dev/null 2>&1; then
  echo 'invalid allowlist unit was accepted' >&2
  exit 1
fi
: > "$TMP_DIR/too-many-units"
for ((index=0; index<1025; index++)); do
  printf 'unit%s.service\n' "$index" >> "$TMP_DIR/too-many-units"
done
if PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/create" root@server \
  "$TMP_DIR/test-key.pub" --user agent \
  --status-allowlist "$TMP_DIR/too-many-units" \
  --log-allowlist "$TMP_DIR/log-allowlist" >/dev/null 2>&1; then
  echo 'oversized allowlist was accepted' >&2
  exit 1
fi

# Exercise request validation and allowlist decisions without touching the
# host's /etc. Only the test copy's configuration path is redirected.
mkdir -p "$TMP_DIR/allowlists"
printf '%s\n' 'allowed.service' > "$TMP_DIR/allowlists/status-allowlist"
printf '%s\n' 'allowed.service' > "$TMP_DIR/allowlists/log-allowlist"
chmod 400 "$TMP_DIR/allowlists/status-allowlist" "$TMP_DIR/allowlists/log-allowlist"
cat > "$TMP_DIR/stat-helper" <<'STAT_HELPER'
#!/usr/bin/env bash
case "$2" in
  %u) printf '%s\n' 0 ;;
  %a) printf '%s\n' 400 ;;
  %s) printf '%s\n' 16 ;;
  *) exit 2 ;;
esac
STAT_HELPER
chmod 755 "$TMP_DIR/stat-helper"
sed -e "s#/etc/homelab-agent-access#$TMP_DIR/allowlists#g" \
  -e "s#/usr/bin/stat#$TMP_DIR/stat-helper#g" \
  -e "s#/bin/stat#$TMP_DIR/stat-helper#g" \
  "$ROOT_DIR/remote/homelab-agent-dispatch-root" > "$TMP_DIR/helper-test"
chmod 755 "$TMP_DIR/helper-test"

run_helper_request() {
  local request="$1"
  printf '%s\n' "$request" | bash "$TMP_DIR/helper-test" \
    > "$TMP_DIR/helper-output" 2>&1
}
expect_helper_rc() {
  local expected="$1" request="$2" rc
  set +e
  run_helper_request "$request"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "unexpected helper exit for '$request': got $rc, expected $expected" >&2
    cat "$TMP_DIR/helper-output" >&2
    exit 1
  fi
}

expect_helper_rc 64 'status --bad'
expect_helper_rc 64 'logs allowed.service 501'
set +e
printf '%s\n%s\n' ports extra | bash "$TMP_DIR/helper-test" \
  > "$TMP_DIR/helper-output" 2>&1
multiple_rc=$?
set -e
[[ "$multiple_rc" -eq 64 ]]

expect_helper_rc 77 'status denied.service'
grep -q 'not allowlisted' "$TMP_DIR/helper-output"
expect_helper_rc 77 'logs denied.service 1'
grep -q 'not allowlisted' "$TMP_DIR/helper-output"

# Allowed requests must pass authorization, although the underlying host command
# may be absent or fail when systemd is not running.
for request in 'status allowed.service' 'logs allowed.service 1'; do
  set +e
  run_helper_request "$request"
  allowed_rc=$?
  set -e
  [[ "$allowed_rc" -ne 77 ]]
  if grep -q 'not allowlisted' "$TMP_DIR/helper-output"; then
    echo "allowlisted request was denied: $request" >&2
    exit 1
  fi
done
chmod 600 "$TMP_DIR/allowlists/status-allowlist"
printf '%s\n' 'invalid unit' >> "$TMP_DIR/allowlists/status-allowlist"
chmod 400 "$TMP_DIR/allowlists/status-allowlist"
expect_helper_rc 69 'status allowed.service'

printf '%s\n' 'CLI and request-validation tests passed.'
