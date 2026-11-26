#!/usr/bin/env bash
set -uo pipefail
module_metadata() { printf 'network|NetSweep|1.0.0|DNS, connectivity, and network diagnostics\n'; }
case "${1:-}" in
  __version) printf '1.0.0\n'; exit 0 ;;
  help|-h|--help) cat <<'EOF'
NetSweep — network diagnostics
Usage: macsweep network
EOF
  exit 0 ;;
esac
printf '== Network configuration ==\n'
if command -v networksetup >/dev/null 2>&1; then networksetup -getairportnetwork en0 2>/dev/null || true; fi
if command -v ifconfig >/dev/null 2>&1; then ifconfig 2>/dev/null | grep -E '^[[:alnum:]]|inet |status:' | head -30; fi
printf '\n== DNS lookup ==\n'
for host in apple.com example.com; do
  if command -v dscacheutil >/dev/null 2>&1; then dscacheutil -q host -a name "$host" 2>/dev/null | grep -m3 -E 'name:|ip_address:' || true
  else getent hosts "$host" 2>/dev/null | head -3 || true
  fi
done
printf '\n== Connectivity ==\n'
ping -c 3 apple.com 2>&1 || true
