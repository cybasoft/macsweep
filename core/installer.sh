#!/usr/bin/env bash

module_checksum() {
  local file="$1"
  if core_have sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  elif core_have shasum; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    return 1
  fi
}

module_trusted_artifact() {
  local url="$1"
  [[ "$url" == https://raw.githubusercontent.com/cybasoft/macsweep/* ||
     "$url" == https://github.com/cybasoft/macsweep/releases/download/* ]]
}

module_install() {
  local id="$1" requested_version="${2:-}"
  module_validate_id "$id" || {
    printf "error: invalid module name: %s\n" "$id" >&2
    return "$MACSWEEP_EXIT_INVALID"
  }
  module_registry_entry "$id" || {
    printf "error: unknown module: %s\n" "$id" >&2
    return "$MACSWEEP_EXIT_INVALID"
  }
  if [[ -n "$requested_version" && "$requested_version" != "$MODULE_VERSION" ]]; then
    printf "error: requested version %s is not available (latest: %s)\n" "$requested_version" "$MODULE_VERSION" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  if module_is_installed "$id"; then
    printf "%s is already installed (version %s).\n" "$MODULE_NAME" "$(module_installed_version "$id")"
    return 0
  fi

  module_trusted_artifact "$MODULE_ARTIFACT" || {
    printf "error: untrusted module artifact source\n" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  }
  mkdir -p "$MACSWEEP_CACHE_DIR" || return "$MACSWEEP_EXIT_INSTALL"
  local temp download checksum
  temp=$(mktemp -d "$MACSWEEP_CACHE_DIR/install.XXXXXX") || return "$MACSWEEP_EXIT_INSTALL"
  download="$temp/module.sh"
  if ! curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
      -- "$MODULE_ARTIFACT" -o "$download"; then
    rm -rf "$temp"
    printf "error: could not download %s\n" "$MODULE_NAME" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  if [[ -z "$MODULE_CHECKSUM" || "$MODULE_CHECKSUM" == "-" ]]; then
    rm -rf "$temp"
    printf "error: %s has no integrity checksum\n" "$MODULE_NAME" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  checksum=$(module_checksum "$download") || {
    rm -rf "$temp"
    printf "error: SHA-256 verification is unavailable\n" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  }
  if [[ "$checksum" != "$MODULE_CHECKSUM" ]]; then
    rm -rf "$temp"
    printf "error: integrity verification failed for %s\n" "$MODULE_NAME" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  chmod 0755 "$download" || { rm -rf "$temp"; return "$MACSWEEP_EXIT_INSTALL"; }
  mkdir -p "$MACSWEEP_MODULE_DIR" || { rm -rf "$temp"; return "$MACSWEEP_EXIT_INSTALL"; }
  if ! mkdir "$MACSWEEP_MODULE_DIR/$id.tmp.$$"; then
    rm -rf "$temp"
    printf "error: could not prepare module directory\n" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  local staged="$MACSWEEP_MODULE_DIR/$id.tmp.$$"
  cp "$download" "$staged/module.sh" || { rm -rf "$temp" "$staged"; return "$MACSWEEP_EXIT_INSTALL"; }
  chmod 0755 "$staged/module.sh"
  if [[ -e "$MACSWEEP_MODULE_DIR/$id" ]]; then
    rm -rf "$staged"
    rm -rf "$temp"
    printf "error: refusing to overwrite existing module: %s\n" "$id" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  if ! mv "$staged" "$MACSWEEP_MODULE_DIR/$id"; then
    rm -rf "$staged" "$temp"
    printf "error: could not install %s\n" "$MODULE_NAME" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  rm -rf "$temp"
  printf "Installed %s %s.\n" "$MODULE_NAME" "$MODULE_VERSION"
  return 0
}

module_uninstall() {
  local id="$1"
  module_validate_id "$id" || {
    printf "error: invalid module name: %s\n" "$id" >&2
    return "$MACSWEEP_EXIT_INVALID"
  }
  module_is_installed "$id" || {
    printf "%s is not installed.\n" "$id"
    return 0
  }
  if core_is_interactive && [[ "${NON_INTERACTIVE:-0}" == "0" ]]; then
    local answer
    read -r -p "Remove $id? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { printf "Aborted.\n"; return 0; }
  fi
  rm -rf "$MACSWEEP_MODULE_DIR/$id" || return "$MACSWEEP_EXIT_INSTALL"
  printf "Removed %s.\n" "$id"
}

module_update_one() {
  local id="$1"
  module_validate_id "$id" || return "$MACSWEEP_EXIT_INVALID"
  module_registry_entry "$id" || return "$MACSWEEP_EXIT_INVALID"
  if module_is_installed "$id"; then
    local installed
    installed=$(module_installed_version "$id")
    if [[ "$installed" == "$MODULE_VERSION" ]]; then
      printf "%s is already at version %s.\n" "$MODULE_NAME" "$MODULE_VERSION"
      return 0
    fi
  fi
  if core_is_interactive && [[ "${NON_INTERACTIVE:-0}" == "0" ]]; then
    local answer
    read -r -p "Update $MODULE_NAME to $MODULE_VERSION? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { printf "Skipped %s.\n" "$MODULE_NAME"; return 0; }
  else
    printf "error: module updates require interactive approval\n" >&2
    return "$MACSWEEP_EXIT_INSTALL"
  fi
  local backup=""
  if module_is_installed "$id"; then
    backup="$MACSWEEP_MODULE_DIR/$id.backup.$$"
    mv "$MACSWEEP_MODULE_DIR/$id" "$backup" || return "$MACSWEEP_EXIT_INSTALL"
  fi
  if module_install "$id"; then
    [[ -z "$backup" ]] || rm -rf "$backup"
    return 0
  else
    local status=$?
    if [[ -n "$backup" && -e "$backup" ]]; then
      mv "$backup" "$MACSWEEP_MODULE_DIR/$id"
    fi
    return "$status"
  fi
}
