#!/usr/bin/env bash
set -uo pipefail
module_metadata() { printf 'json|JSONSweep|1.0.0|JSON formatting, validation, comparison, and querying\n'; }
case "${1:-}" in
  __version) printf '1.0.0\n'; exit 0 ;;
  help|-h|--help) cat <<'EOF'
JSONSweep — JSON tools
Usage:
  macsweep json pretty <file>
  macsweep json validate <file>
  macsweep json diff <file1> <file2>
  macsweep json query <file> <jsonpath>
EOF
  exit 0 ;;
esac
subcommand="${1:-}"
shift || true
if command -v jq >/dev/null 2>&1; then
  formatter=jq
else
  formatter=python3
fi
case "$subcommand" in
  pretty)
    [[ -n "${1:-}" && -f "$1" ]] || { printf 'error: file required\n' >&2; exit 2; }
    if [[ "$formatter" == jq ]]; then jq '.' "$1"; else python3 -m json.tool "$1"; fi
    ;;
  validate)
    [[ -n "${1:-}" && -f "$1" ]] || { printf 'error: file required\n' >&2; exit 2; }
    if [[ "$formatter" == jq ]]; then jq empty "$1" >/dev/null; else python3 -m json.tool "$1" >/dev/null; fi
    printf 'Valid JSON: %s\n' "$1"
    ;;
  diff)
    [[ -n "${1:-}" && -n "${2:-}" ]] || { printf 'error: two files required\n' >&2; exit 2; }
    diff -u "$1" "$2" || true
    ;;
  query)
    [[ -n "${1:-}" ]] || { printf 'error: file required\n' >&2; exit 2; }
    file="$1"; query="${2:-.}"
    if [[ "$formatter" == jq ]]; then jq "$query" "$file"; else
      python3 - "$file" "$query" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    value = json.load(f)
key = sys.argv[2].strip(".")
for part in key.split(".") if key else []:
    if isinstance(value, dict):
        value = value[part]
    elif isinstance(value, list):
        value = value[int(part)]
print(json.dumps(value, indent=2))
PY
    fi
    ;;
  *) printf 'error: unknown json subcommand: %s\n' "$subcommand" >&2; exit 2 ;;
esac
