#!/usr/bin/env bash
set -uo pipefail
module_metadata() { printf 'ports|PortSweep|1.0.0|Inspect listening ports and processes\n'; }
case "${1:-}" in
  __version) printf '1.0.0\n'; exit 0 ;;
  help|-h|--help) cat <<'EOF'
PortSweep — inspect listening ports
Usage: macsweep ports [port]
  macsweep ports          List listening TCP ports
  macsweep ports 3000     Show processes listening on port 3000
EOF
  exit 0 ;;
esac
if ! command -v lsof >/dev/null 2>&1; then printf 'error: lsof is unavailable\n' >&2; exit 5; fi
port="${1:-}"
if [[ -n "$port" ]]; then
  if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then printf 'error: invalid port: %s\n' "$port" >&2; exit 2; fi
  lsof -nP "-iTCP:${port}" -sTCP:LISTEN
else
  lsof -nP -iTCP -sTCP:LISTEN
fi
