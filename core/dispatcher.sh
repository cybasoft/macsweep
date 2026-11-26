#!/usr/bin/env bash

usage_main() {
  cat <<'EOF'
macsweep <command> [options]

Core commands:
  system health             Show macOS health and security status
  system optimize           Run preview-first maintenance
  system updates            List macOS software updates
  clean system              Preview or clear selected user cleanup targets
  clean dev                 Preview or clean developer caches and tool data
  clean large [dir] [MB]    Find large files and top-level folders
  apps uninstall <name>     Preview or remove an app and exact leftovers
  startup                   Inspect login items and launch plist files

Optional modules:
  ports [port]              Inspect listeners and resolve process conflicts
  network                   Run DNS and connectivity diagnostics
  doctor                    Diagnose development environment configuration
  files <subcommand>        Inspect symlinks, permissions, attributes, or metadata
  json <subcommand>         Validate, format, compare, or query JSON

Module management:
  list                      List installed and available modules
  install <module>          Install an optional module
  uninstall <module>        Remove an optional module
  update [module]           Update one or all installed modules

Global options:
  --help, -h                Show help
  --version                 Show MacSweep version
  --non-interactive         Never prompt
  --list                    Alias for list

Safety:
  Existing cleanup and maintenance commands remain preview-first.
  Destructive commands require --apply or explicit confirmation.

Compatibility aliases:
  health, clean, dev, all, uninstall, large, startup, optimize, updates

See README.md for full command mapping.
EOF
}

dispatch_module() {
  local id="$1"
  shift
  if ! module_is_installed "$id"; then
    printf "%s is not installed.\n" "$(module_registry_name "$id")" >&2
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
      printf "Install it with: macsweep install %s\n" "$id" >&2
      return "$MACSWEEP_EXIT_MISSING"
    fi
    if core_is_interactive; then
      local answer name version
      if module_registry_entry "$id"; then
        name="$MODULE_NAME"
        version="$MODULE_VERSION"
      else
        printf "Unknown module: %s\n" "$id" >&2
        return "$MACSWEEP_EXIT_INVALID"
      fi
      read -r -p "$name $version is not installed. Install $name now? [Y/n] " answer
      answer=${answer:-Y}
      if [[ "$answer" == "Y" || "$answer" == "y" ]]; then
        module_install "$id" || return "$?"
      else
        printf "No changes made.\n"
        return "$MACSWEEP_EXIT_MISSING"
      fi
    else
      printf "Install it with: macsweep install %s\n" "$id" >&2
      return "$MACSWEEP_EXIT_MISSING"
    fi
  fi
  "$MACSWEEP_MODULE_DIR/$id/module.sh" "$@"
}

module_registry_name() {
  if module_registry_entry "$1"; then
    printf '%s\n' "$MODULE_NAME"
  else
    printf '%s\n' "$1"
  fi
}

cmd_list() {
  printf "Installed modules:\n"
  local found=0 id line rid name version description
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "${line:0:1}" != "#" ]] || continue
    IFS='|' read -r rid name version description artifact checksum minimum <<< "$line"
    if module_is_installed "$rid"; then
      printf "  %-9s %-18s %s\n" "$rid" "$name" "$(module_installed_version "$rid")"
      found=1
    fi
  done < "$MACSWEEP_REGISTRY_FILE"
  (( found )) || printf "  (none)\n"

  printf "\nAvailable modules:\n"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "${line:0:1}" != "#" ]] || continue
    IFS='|' read -r rid name version description artifact checksum minimum <<< "$line"
    if module_is_installed "$rid"; then
      status="installed"
    else
      status="not installed"
    fi
    printf "  %-9s %-18s %-12s %s\n" "$rid" "$name" "$version" "$description"
    printf "    %s\n" "$status"
  done < "$MACSWEEP_REGISTRY_FILE"
}

cmd_update_all() {
  local line rid name version description artifact checksum minimum
  local changed=0
  [[ -f "$MACSWEEP_REGISTRY_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "${line:0:1}" != "#" ]] || continue
    IFS='|' read -r rid name version description artifact checksum minimum <<< "$line"
    if module_is_installed "$rid"; then
      module_update_one "$rid" || return "$?"
      changed=1
    fi
  done < "$MACSWEEP_REGISTRY_FILE"
  (( changed )) || printf "No modules are installed.\n"
}
