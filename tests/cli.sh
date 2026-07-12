#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ssh-keygen -q -t ed25519 -N '' -f "$TMP_DIR/test-key"
printf '%s\n' "$(sed 's/ [^ ]*$/ agent test/' "$TMP_DIR/test-key.pub")" > "$TMP_DIR/test-key.pub"
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${FAKE_SSH_CAPTURE:?}"
FAKE_SSH
chmod +x "$TMP_DIR/bin/ssh"

FAKE_SSH_CAPTURE="$TMP_DIR/ssh.args" \
PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/bin/create" root@server "$TMP_DIR/test-key.pub" --user agent \
  >/dev/null

args=()
while IFS= read -r arg; do
  args+=("$arg")
done < "$TMP_DIR/ssh.args"
[[ ${#args[@]} -eq 17 ]]
[[ "${args[9]}" == root@server ]]
[[ "${args[13]}" == agent ]]
for index in 14 15 16; do
  [[ "${args[$index]}" =~ ^[A-Za-z0-9+/=]+$ ]]
done

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
  "$TMP_DIR/test-key.pub" --user 'bad;name' >/dev/null 2>&1; then
  echo 'invalid username was accepted' >&2
  exit 1
fi

if printf '%s\n' 'status --bad' | bash "$ROOT_DIR/remote/homelab-agent-dispatch-root" \
  >/dev/null 2>&1; then
  echo 'invalid status request was accepted' >&2
  exit 1
fi

if printf '%s\n' 'logs example.service 501' | \
  bash "$ROOT_DIR/remote/homelab-agent-dispatch-root" >/dev/null 2>&1; then
  echo 'oversized log request was accepted' >&2
  exit 1
fi

if printf '%s\n%s\n' ports extra | \
  bash "$ROOT_DIR/remote/homelab-agent-dispatch-root" >/dev/null 2>&1; then
  echo 'multiple request lines were accepted' >&2
  exit 1
fi

printf '%s\n' 'CLI and request-validation tests passed.'
