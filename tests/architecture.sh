#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT
export HOME="$TEMP_ROOT/home"
export MACSWEEP_MODULE_DIR="$TEMP_ROOT/modules"
export MACSWEEP_CACHE_DIR="$TEMP_ROOT/cache"
mkdir -p "$HOME"

bash -n "$SCRIPT_DIR/macsweep.sh"
"$SCRIPT_DIR/macsweep.sh" --help >"$TEMP_ROOT/help"
grep -q "macsweep <command>" "$TEMP_ROOT/help"
"$SCRIPT_DIR/macsweep.sh" --version >"$TEMP_ROOT/version"
grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$" "$TEMP_ROOT/version"
"$SCRIPT_DIR/macsweep.sh" list >"$TEMP_ROOT/list"
grep -q "PortSweep" "$TEMP_ROOT/list"
"$SCRIPT_DIR/macsweep.sh" --non-interactive network >"$TEMP_ROOT/output" 2>&1 && exit 1 || status=$?
[[ "$status" -eq 3 ]]
grep -q "macsweep install network" "$TEMP_ROOT/output"

if "$SCRIPT_DIR/macsweep.sh" install '../ports' >/dev/null 2>&1; then
  printf 'FAIL: invalid module name was accepted\n' >&2
  exit 1
fi

mkdir -p "$TEMP_ROOT/modules/ports"
cp "$SCRIPT_DIR/tools/ports/module.sh" "$TEMP_ROOT/modules/ports/module.sh"
chmod 0755 "$TEMP_ROOT/modules/ports/module.sh"
"$SCRIPT_DIR/macsweep.sh" ports --help | grep -q "PortSweep"

printf 'PASS: help, registry, missing-module, validation, and dispatch checks\n'
