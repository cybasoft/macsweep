#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$SCRIPT_DIR/macsweep.sh"

TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT
export HOME="$TEMP_ROOT/home"
mkdir -p "$HOME/inside" "$TEMP_ROOT/outside"
printf test > "$HOME/inside/item"
printf keep > "$TEMP_ROOT/outside/item"
ln -s "$TEMP_ROOT/outside" "$HOME/linked"

if ! safe_path "$HOME/inside"; then
  printf 'FAIL: in-home directory rejected\n' >&2
  exit 1
fi
if safe_path "$HOME/linked"; then
  printf 'FAIL: symlink outside HOME accepted\n' >&2
  exit 1
fi

APPLY=1
clean_dir "test target" "$HOME/inside"
if [[ -e "$HOME/inside/item" || ! -f "$TEMP_ROOT/outside/item" ]]; then
  printf 'FAIL: cleanup did not stay within HOME\n' >&2
  exit 1
fi

mkdir -p \
  "$HOME/Applications/MacSweepTest.app" \
  "$HOME/Library/Application Support/com.example.macsweep-test" \
  "$HOME/Library/Application Support/com.example.macsweep-test.helper" \
  "$HOME/Library/Application Support/MacSweepTest" \
  "$HOME/Library/Preferences"
touch "$HOME/Library/Preferences/com.example.macsweep-test.plist"

mdls() { printf 'com.example.macsweep-test\n'; }
APPLY=0
uninstall_output=$(cmd_uninstall MacSweepTest)
if [[ "$uninstall_output" != *"$HOME/Library/Application Support/com.example.macsweep-test"* ||
      "$uninstall_output" != *"$HOME/Library/Preferences/com.example.macsweep-test.plist"* ||
      "$uninstall_output" == *"com.example.macsweep-test.helper"* ||
      "$uninstall_output" == *"$HOME/Library/Application Support/MacSweepTest"* ]]; then
  printf 'FAIL: uninstall candidates were not narrowly matched\n' >&2
  exit 1
fi

docker() {
  if [[ "$1" == "info" ]]; then
    return 0
  fi
  if [[ "$1" == "system" && "$2" == "df" ]]; then
    printf 'Docker storage fixture\n'
  fi
}
brew() { printf 'Homebrew cleanup fixture\n'; }

DOCKER_PRUNE=0
dev_output=$(cmd_dev)
if [[ "$dev_output" != *"not pruning"* ]]; then
  printf 'FAIL: Docker prune was not disabled by default\n' >&2
  exit 1
fi
DOCKER_PRUNE=1
dev_output=$(cmd_dev)
if [[ "$dev_output" != *"docker system prune -f"* ]]; then
  printf 'FAIL: Docker prune opt-in was not previewed\n%s\n' "$dev_output" >&2
  exit 1
fi

printf 'PASS: cleanup containment, uninstall matching, and Docker opt-in\n'