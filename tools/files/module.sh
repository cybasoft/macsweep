#!/usr/bin/env bash
set -uo pipefail
module_metadata() { printf 'files|FileSweep|1.0.0|Filesystem inspection and metadata checks\n'; }
case "${1:-}" in
  __version) printf '1.0.0\n'; exit 0 ;;
  help|-h|--help) cat <<'EOF'
FileSweep — inspect filesystem metadata
Usage:
  macsweep files symlinks [path]
  macsweep files permissions [path]
  macsweep files attributes [path]
  macsweep files hidden [path]
  macsweep files info <path>
EOF
  exit 0 ;;
esac
subcommand="${1:-info}"
shift || true
path="${1:-.}"
case "$subcommand" in
  symlinks)
    [[ -d "$path" ]] || { printf 'error: not a directory: %s\n' "$path" >&2; exit 2; }
    find "$path" -type l -! -exec test -e {} \; -print 2>/dev/null
    ;;
  permissions)
    [[ -d "$path" ]] || { printf 'error: not a directory: %s\n' "$path" >&2; exit 2; }
    find "$path" -exec ls -lde {} + 2>/dev/null
    ;;
  attributes|xattrs)
    [[ -e "$path" ]] || { printf 'error: not found: %s\n' "$path" >&2; exit 2; }
    if command -v xattr >/dev/null 2>&1; then xattr -l "$path"; else ls -lO "$path"; fi
    ;;
  hidden)
    [[ -d "$path" ]] || { printf 'error: not a directory: %s\n' "$path" >&2; exit 2; }
    find "$path" -name '.*' -print 2>/dev/null
    ;;
  info)
    [[ -e "$path" ]] || { printf 'error: not found: %s\n' "$path" >&2; exit 2; }
    ls -lde "$path"
    if command -v stat >/dev/null 2>&1; then stat "$path"; fi
    if command -v mdls >/dev/null 2>&1; then mdls "$path" 2>/dev/null | head -40; fi
    ;;
  *) printf 'error: unknown files subcommand: %s\n' "$subcommand" >&2; exit 2 ;;
esac
