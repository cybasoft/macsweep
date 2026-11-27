#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT
export HOME="$TEMP_ROOT/home"
export MACSWEEP_MODULE_DIR="$TEMP_ROOT/modules"
export MACSWEEP_CACHE_DIR="$TEMP_ROOT/cache"
export MACSWEEP_REGISTRY_FILE="$TEMP_ROOT/modules.tsv"
mkdir -p "$HOME" "$TEMP_ROOT/bin"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Mock curl mirrors real curl's argument handling: options must come before "--",
# exactly one URL may follow it, and the call is logged.
cat > "$TEMP_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
[[ "${MOCK_CURL_FAIL:-0}" == "1" ]] && exit 22
out="" urls=() after=0
while (( $# )); do
  if (( after )); then urls+=("$1")
  elif [[ "$1" == "--" ]]; then after=1
  elif [[ "$1" == "--output" || "$1" == "-o" ]]; then out="$2"; shift
  fi
  shift
done
(( ${#urls[@]} == 1 )) || { echo "curl: too many URLs" >&2; exit 3; }
[[ -n "$out" ]] || { cat "$MOCK_CURL_SOURCE"; exit 0; }
cp "$MOCK_CURL_SOURCE" "$out"
EOF
chmod +x "$TEMP_ROOT/bin/curl"
export PATH="$TEMP_ROOT/bin:$PATH"
export MOCK_CURL_LOG="$TEMP_ROOT/curl.log"
export MOCK_CURL_SOURCE="$SCRIPT_DIR/tools/ports/module.sh"
: > "$MOCK_CURL_LOG"

good_sum=$(shasum -a 256 "$MOCK_CURL_SOURCE" | awk '{print $1}')
good_url="https://raw.githubusercontent.com/cybasoft/macsweep/v0.1.1/tools/ports/module.sh"
write_registry() { printf 'ports|PortSweep|1.0.0|test|%s|%s|0.1.0\n' "$1" "$2" > "$MACSWEEP_REGISTRY_FILE"; }
ms() { "$SCRIPT_DIR/macsweep.sh" "$@"; }
no_temp_left() { [[ -z "$(ls -A "$MACSWEEP_CACHE_DIR" 2>/dev/null)" ]] || fail "temporary files left in cache"; }

# Invalid checksum: nothing installed, temp files cleaned up.
write_registry "$good_url" "$(printf '0%.0s' {1..64})"
if ms install ports >/dev/null 2>&1; then fail "bad checksum was accepted"; fi
[[ ! -e "$MACSWEEP_MODULE_DIR/ports" ]] || fail "module installed despite bad checksum"
no_temp_left

# Untrusted URL: rejected before any download.
write_registry "https://example.com/module.sh" "$good_sum"
: > "$MOCK_CURL_LOG"
if ms install ports >/dev/null 2>&1; then fail "untrusted URL was accepted"; fi
[[ ! -s "$MOCK_CURL_LOG" ]] || fail "untrusted URL was downloaded"

# Failed download: nothing installed, temp files cleaned up.
write_registry "$good_url" "$good_sum"
if MOCK_CURL_FAIL=1 ms install ports >/dev/null 2>&1; then fail "failed download reported success"; fi
[[ ! -e "$MACSWEEP_MODULE_DIR/ports" ]] || fail "module installed after failed download"
no_temp_left

# Successful install, then the module runs through the dispatcher.
ms install ports >/dev/null || fail "valid install failed"
[[ -x "$MACSWEEP_MODULE_DIR/ports/module.sh" ]] || fail "module not installed"
no_temp_left
ms ports --help | grep -q "PortSweep" || fail "installed module did not run"

# Existing modules are never silently overwritten.
printf '#!/usr/bin/env bash\necho custom\n' > "$MACSWEEP_MODULE_DIR/ports/module.sh"
ms install ports >/dev/null 2>&1 || true
grep -q custom "$MACSWEEP_MODULE_DIR/ports/module.sh" || fail "existing module was overwritten"

# Removal leaves other state alone.
ms --non-interactive uninstall ports >/dev/null
[[ ! -e "$MACSWEEP_MODULE_DIR/ports" ]] || fail "module was not removed"

# Path traversal in module names is rejected.
if ms install '../ports' >/dev/null 2>&1; then fail "path traversal accepted"; fi

printf 'PASS: install, integrity, trusted-source, overwrite, and cleanup checks\n'
