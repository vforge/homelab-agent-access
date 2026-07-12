#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in \
  "$ROOT_DIR/bin/ssh-readonly-user/create" \
  "$ROOT_DIR/bin/ssh-readonly-user/list" \
  "$ROOT_DIR/bin/ssh-readonly-user/remove"; do
  printf 'Checking %s\n' "${script#"$ROOT_DIR/"}"
  bash -n "$script"
done
