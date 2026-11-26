#!/usr/bin/env bash
set -uo pipefail
module_metadata() { printf 'doctor|DevSweep|1.0.0|Development environment diagnostics\n'; }
case "${1:-}" in
  __version) printf '1.0.0\n'; exit 0 ;;
  help|-h|--help) cat <<'EOF'
DevSweep — development environment diagnostics
Usage: macsweep doctor
EOF
  exit 0 ;;
esac
printf '== Shell and PATH ==\nShell: %s\nPATH:\n' "${SHELL:-unknown}"
printf '%s\n' "$PATH" | tr ':' '\n' | sed 's/^/  /'
for tool in node npm python3 php ruby git docker brew; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '\n== %s ==\n' "$tool"
    case "$tool" in
      node) node --version ;;
      npm) npm --version ;;
      python3) python3 --version ;;
      php) php --version | head -1 ;;
      ruby) ruby --version ;;
      git) git --version ;;
      docker) docker --version 2>&1 ;;
      brew) brew --version 2>/dev/null | head -3 ;;
    esac
  fi
done
