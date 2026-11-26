#!/usr/bin/env bash

MACSWEEP_EXIT_INVALID=2
MACSWEEP_EXIT_MISSING=3
MACSWEEP_EXIT_INSTALL=4
MACSWEEP_EXIT_UNSUPPORTED=5

core_die() {
  printf "error: %s\n" "$*" >&2
  exit "$MACSWEEP_EXIT_INVALID"
}

core_warn() {
  printf "warning: %s\n" "$*" >&2
}

core_have() {
  command -v "$1" >/dev/null 2>&1
}

core_is_interactive() {
  [[ -t 0 && -t 1 ]]
}

core_version() {
  printf '%s\n' "${MACSWEEP_VERSION:-1.0.0}"
}
