#!/usr/bin/env bash

MACSWEEP_REGISTRY_FILE="${MACSWEEP_REGISTRY_FILE:-${MACSWEEP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/modules.tsv}"
MACSWEEP_SHARE_DIR="${MACSWEEP_SHARE_DIR:-$HOME/.local/share/macsweep}"
MACSWEEP_MODULE_DIR="${MACSWEEP_MODULE_DIR:-$MACSWEEP_SHARE_DIR/modules}"
MACSWEEP_CACHE_DIR="${MACSWEEP_CACHE_DIR:-$MACSWEEP_SHARE_DIR/cache}"

module_validate_id() {
  [[ "$1" =~ ^[a-z][a-z0-9-]*$ ]]
}

module_registry_entry() {
  local id="$1" line
  module_validate_id "$id" || return 1
  [[ -f "$MACSWEEP_REGISTRY_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "${line:0:1}" != "#" ]] || continue
    IFS='|' read -r rid name version description artifact checksum minimum <<< "$line"
    if [[ "$rid" == "$id" ]]; then
      MODULE_ID="$rid"
      MODULE_NAME="$name"
      MODULE_VERSION="$version"
      MODULE_DESCRIPTION="$description"
      MODULE_ARTIFACT="$artifact"
      MODULE_CHECKSUM="$checksum"
      MODULE_MINIMUM="$minimum"
      return 0
    fi
  done < "$MACSWEEP_REGISTRY_FILE"
  return 1
}

module_is_installed() {
  local id="$1"
  module_validate_id "$id" || return 1
  [[ -f "$MACSWEEP_MODULE_DIR/$id/module.sh" && -x "$MACSWEEP_MODULE_DIR/$id/module.sh" ]]
}

module_installed_version() {
  local id="$1"
  module_is_installed "$id" || return 1
  local version=""
  if [[ -x "$MACSWEEP_MODULE_DIR/$id/module.sh" ]]; then
    version=$("$MACSWEEP_MODULE_DIR/$id/module.sh" __version 2>/dev/null) || version=""
  fi
  printf '%s\n' "${version:-unknown}"
}

module_available_ids() {
  local line rid
  [[ -f "$MACSWEEP_REGISTRY_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "${line:0:1}" != "#" ]] || continue
    rid=${line%%|*}
    printf '%s\n' "$rid"
  done
}
