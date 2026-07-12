#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in \
  "$ROOT_DIR/bin/create" \
  "$ROOT_DIR/bin/list" \
  "$ROOT_DIR/bin/remove"; do
  printf 'Checking %s\n' "${script#"$ROOT_DIR/"}"
  bash -n "$script"
done
