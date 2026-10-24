#!/usr/bin/env bash
#
# macsweep — a small, readable, auditable Mac health/cleanup tool.
#
# SAFE BY DEFAULT: every command is a dry run. Nothing is deleted or changed
# until you pass --apply.
#
# Install:
#   mkdir -p ~/bin && cp macsweep.sh ~/bin/macsweep && chmod +x ~/bin/macsweep
#   (make sure ~/bin is in your PATH)
#
# Usage:  macsweep <command> [options]
#   health                 Disk, memory, CPU hogs, battery, SMART, security status
#   clean                  User caches, logs, Trash, mail downloads (+ report-only items)
#   dev                    Developer junk: Xcode, brew, npm, pnpm, gradle, docker, etc.
#   all                    clean + dev
#   uninstall <App Name>   Find an app plus its leftovers, move them to Trash
#   large [dir] [minMB]    Find big files (default: $HOME, 500 MB) + top folders
#   startup                List login items, launch agents and daemons
#   optimize               Flush DNS, purge RAM cache, reset QuickLook cache
#   updates                List available macOS software updates
#   help                   Show this help
#
# Options:
#   --apply, -a            Actually do it (default is dry run)
#   --yes, -y              Skip the move-to-Trash confirmation (uninstall)
#   --docker-prune         dev/all: prune Docker data when explicitly requested
#   --launchservices       optimize: also rebuild the Launch Services DB
#   --spotlight            optimize: also rebuild the Spotlight index (slow)
#
# Examples:
#   macsweep health
#   macsweep all                 # preview what would be freed
#   macsweep all --apply         # do it
#   macsweep uninstall "Slack"   # preview
#   macsweep uninstall "Slack" --apply
#   macsweep uninstall "CleanMyMac X" --apply  # asks before quitting if running
#   macsweep large ~/Downloads 200

set -uo pipefail

APPLY=0
YES=0
LSREG=0
SPOT=0
DOCKER_PRUNE=0
TOTAL_KB=0
SKIP_CLEAN=("")
SAFE_PATH=""

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi

# ---------- helpers ----------------------------------------------------------

die()    { printf "%s\n" "${RED}error:${RST} $*" >&2; exit 1; }
warn()   { printf "%s\n" "${YLW}warn:${RST} $*" >&2; }
header() { printf "\n%s\n" "${BOLD}${CYN}== $* ==${RST}"; }
have()   { command -v "$1" >/dev/null 2>&1; }

human() {
  awk -v k="${1:-0}" 'BEGIN{
    if (k >= 1048576)      printf "%.2f GB", k/1048576;
    else if (k >= 1024)    printf "%.1f MB", k/1024;
    else                   printf "%d KB", k }'
}

kb_of() {
  local v
  v=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
  echo "${v:-0}"
}

# Resolve the target before allowing deletion, so symlinked paths cannot escape HOME.
safe_path() {
  local home_real path_real
  SAFE_PATH=""
  [[ -n "$1" && -d "$1" ]] || return 1
  home_real=$(cd -P "$HOME" 2>/dev/null && pwd -P) || return 1
  path_real=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  [[ "$home_real" != "/" && "$path_real" == "$home_real/"* ]] || return 1
  SAFE_PATH="$path_real"
}

prompt_clean_skips() {
  [[ -t 0 ]] || return 0

  header "Cleanup targets"
  printf "  1  User caches (~/Library/Caches)\n"
  printf "  2  User logs (~/Library/Logs)\n"
  printf "  3  Mail attachment downloads\n"
  printf "  4  Trash (needs Full Disk Access)\n"
  printf "  Downloads (~/Downloads) remains review-only and is never auto-deleted.\n"

  local response number
  local selected=()
  read -r -p "Numbers to skip, separated by spaces or commas [none]: " response || response=""
  IFS=', ' read -r -a selected <<< "skip $response"
  for number in "${selected[@]:1}"; do
    case "$number" in
      1|2|3|4) SKIP_CLEAN+=("$number") ;;
      "") ;;
      *) warn "ignoring invalid cleanup target number: $number" ;;
    esac
  done
}

# Empty a directory (keeps the directory itself). Dry-run unless --apply.
clean_dir() {
  local label="$1" dir="$2" number="${3:-}" skip target
  for skip in "${SKIP_CLEAN[@]}"; do
    if [[ -n "$number" && "$skip" == "$number" ]]; then
      printf "  ${YLW}skipped${RST}     %s\n" "$label"
      return 0
    fi
  done
  [[ -d "$dir" ]] || return 0
  local kb; kb=$(kb_of "$dir")
  (( kb > 0 )) || return 0
  if (( APPLY )); then
    if safe_path "$dir"; then
      target="$SAFE_PATH"
      if find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; then
        local remaining; remaining=$(kb_of "$target")
        local removed=$(( kb - remaining ))
        (( removed < 0 )) && removed=0
        (( removed > 0 )) && TOTAL_KB=$(( TOTAL_KB + removed ))
        printf "  ${GRN}cleaned${RST}     %-36s %s\n" "$label" "$(human "$removed")"
      else
        local remaining; remaining=$(kb_of "$target")
        local removed=$(( kb - remaining ))
        (( removed < 0 )) && removed=0
        (( removed > 0 )) && TOTAL_KB=$(( TOTAL_KB + removed ))
        warn "cleanup incomplete: $dir"
        printf "  ${YLW}partial${RST}     %-36s %s\n" "$label" "$(human "$removed")"
      fi
    else
      warn "refusing unsafe path or symlink target: $dir"
    fi
  else
    TOTAL_KB=$(( TOTAL_KB + kb ))
    printf "  ${DIM}would free${RST}  %-36s %s\n" "$label" "$(human "$kb")"
  fi
}

# Run a tool command. Dry-run just prints it.
run_cmd() {
  local label="$1"; shift
  if (( APPLY )); then
    printf "  ${GRN}running${RST}     %s\n" "$label"
    "$@" >/dev/null 2>&1 || warn "'$label' returned non-zero"
  else
    printf "  ${DIM}would run${RST}   %s\n" "$label"
  fi
}

report_size() {
  local label="$1" path="$2"
  [[ -e "$path" ]] || return 0
  printf "  ${YLW}review${RST}      %-36s %s\n" "$label" "$(human "$(kb_of "$path")")"
}

banner() {
  if (( APPLY )); then
    printf "%s\n" "${RED}${BOLD}APPLY MODE — changes will be made.${RST}"
  else
    printf "%s\n" "${GRN}${BOLD}DRY RUN — nothing will be changed. Add --apply to execute.${RST}"
  fi
}

summary() {
  printf "\n%s\n" "${BOLD}$( (( APPLY )) && echo "Freed" || echo "Reclaimable" ): $(human "$TOTAL_KB")${RST}"
}

# ---------- health -----------------------------------------------------------

cmd_health() {
  header "System"
  printf "macOS:   %s (%s)\n" "$(sw_vers -productVersion)" "$(uname -m)"
  printf "Uptime: %s\n" "$(uptime | sed 's/^.*up //; s/,  *[0-9]* users.*//')"

  header "Disk"
  df -h / | awk 'NR==1{print} NR==2{print}'
  diskutil info / 2>/dev/null | grep -E "SMART Status|Solid State" | sed 's/^ *//'
  local snaps; snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple")
  printf "Time Machine local snapshots: %s\n" "$snaps"

  header "Memory"
  memory_pressure 2>/dev/null | grep -E "free percentage" | sed 's/^/  /'
  sysctl vm.swapusage 2>/dev/null | sed 's/^/  /'

  header "Top CPU processes"
  ps -Arcxo %cpu,%mem,comm 2>/dev/null | head -6
  header "Top memory processes"
  ps -Amcxo %mem,%cpu,comm 2>/dev/null | head -6

  header "Battery"
  if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
    pmset -g batt | sed -n '2p' | sed 's/^ *//'
    system_profiler SPPowerDataType 2>/dev/null | grep -E "Cycle Count|Condition|Maximum Capacity" | sed 's/^ */  /'
  else
    echo "  No battery detected."
  fi

  header "Security"
  printf "  SIP:        %s\n" "$(csrutil status 2>/dev/null | sed 's/.*: //')"
  printf "  FileVault:  %s\n" "$(fdesetup status 2>/dev/null | head -1)"
  printf "  Gatekeeper: %s\n" "$(spctl --status 2>/dev/null)"
  printf "  Firewall:   %s\n" "$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | sed 's/\.$//')"

  if have brew; then
    header "Homebrew"
    printf "  Outdated packages: %s\n" "$(brew outdated 2>/dev/null | wc -l | tr -d ' ')"
  fi
}

# ---------- clean ------------------------------------------------------------

cmd_clean() {
  banner
  prompt_clean_skips
  header "System junk"
  clean_dir "User caches (~/Library/Caches)"  "$HOME/Library/Caches" 1
  clean_dir "User logs (~/Library/Logs)"      "$HOME/Library/Logs" 2
  clean_dir "Mail attachment downloads"       "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" 3
  clean_dir "Trash (needs Full Disk Access)"  "$HOME/.Trash" 4

  header "Review manually (never auto-deleted)"
  report_size "iOS device backups"   "$HOME/Library/Application Support/MobileSync/Backup"
  report_size "Downloads folder"     "$HOME/Downloads"
  report_size "Xcode Archives"       "$HOME/Library/Developer/Xcode/Archives"
  local snaps; snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple")
  (( snaps > 0 )) && printf "  ${YLW}review${RST}      Time Machine local snapshots: %s (tmutil deletelocalsnapshots <date>)\n" "$snaps"

  summary
}

# ---------- dev --------------------------------------------------------------

cmd_dev() {
  banner
  header "Developer junk"

  clean_dir "Xcode DerivedData"        "$HOME/Library/Developer/Xcode/DerivedData"
  clean_dir "Xcode iOS DeviceSupport"  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  have xcrun && run_cmd "xcrun simctl delete unavailable" xcrun simctl delete unavailable

  clean_dir "npm cache"                "$HOME/.npm/_cacache"
  clean_dir "Composer cache"           "$HOME/.composer/cache"
  clean_dir "Gradle caches (re-downloads)" "$HOME/.gradle/caches"
  have pnpm && run_cmd "pnpm store prune" pnpm store prune

  if have brew; then
    if (( APPLY )); then
      run_cmd "brew cleanup -s --prune=all" brew cleanup -s --prune=all
    else
      printf "  %s%s%s   brew cleanup (preview below)\n" "$DIM" "would run" "$RST"
      brew cleanup -n 2>/dev/null | tail -3 | sed 's/^/      /'
    fi
  fi

  if have docker && docker info >/dev/null 2>&1; then
    printf "  %s%s%s      stopped containers, dangling images, unused networks:\n" "$YLW" "docker" "$RST"
    docker system df 2>/dev/null | sed 's/^/      /'
    if (( DOCKER_PRUNE )); then
      run_cmd "docker system prune -f (removes stopped containers and unused data)" docker system prune -f
    else
      printf "  %snot pruning%s  pass --docker-prune to remove stopped containers and unused data\n" "$DIM" "$RST"
    fi
  fi

  summary
  printf "%s\n" "${DIM}(brew/pnpm/docker/simctl savings aren't counted in the total.)${RST}"
}

# ---------- uninstall --------------------------------------------------------

cmd_uninstall() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "usage: macsweep uninstall \"App Name\" [--apply]"
  [[ "$name" != */* && "$name" != "." && "$name" != ".." ]] || die "app name must not contain a path"
  banner

  local app=""
  local d
  for d in /Applications "$HOME/Applications"; do
    [[ -d "$d/$name.app" ]] && { app="$d/$name.app"; break; }
  done
  [[ -n "$app" ]] || die "could not find '$name.app' in /Applications or ~/Applications"

  local bid
  bid=$(mdls -name kCFBundleIdentifier -raw "$app" 2>/dev/null)
  [[ "$bid" == "(null)" ]] && bid=""
  printf "App:        %s\nBundle ID:  %s\n" "$app" "${bid:-unknown}"

  local app_running=0
  if pgrep -x "$name" >/dev/null 2>&1; then
    warn "'$name' appears to be running."
    app_running=1
  fi

  local locs=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Preferences"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Logs"
    "$HOME/Library/HTTPStorages"
    "$HOME/Library/WebKit"
    "$HOME/Library/Cookies"
    "$HOME/Library/LaunchAgents"
  )

  local items=("$app")
  local l p existing duplicate
  for l in "${locs[@]}"; do
    [[ -d "$l" ]] || continue
    if [[ -n "$bid" ]]; then
      while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        duplicate=0
        for existing in "${items[@]}"; do
          [[ "$existing" == "$p" ]] && { duplicate=1; break; }
        done
        (( duplicate )) || items+=("$p")
      done < <(find "$l" -maxdepth 1 \( -iname "$bid" -o -iname "$bid.plist" \) 2>/dev/null)
    fi
  done

  header "Found"
  local total=0 kb
  for p in "${items[@]}"; do
    kb=$(kb_of "$p"); total=$(( total + kb ))
    printf "  %-9s %s\n" "$(human "$kb")" "$p"
  done
  printf "\n%s\n" "${BOLD}Total: $(human "$total")${RST}"
  printf "%s\n" "${DIM}Only exact bundle-ID matches are included; other app data is left untouched.${RST}"

  if (( ! APPLY )); then
    (( app_running )) && printf "  %sApply mode will ask whether to quit it before uninstalling.%s\n" "$DIM" "$RST"
    return 0
  fi

  if (( ! YES )); then
    read -r -p "Move these ${#items[@]} items to the Trash? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; return 0; }
  fi

  if (( app_running )); then
    read -r -p "Quit '$name' gracefully and continue uninstalling? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted; the app was left running."; return 0; }
    if ! osascript -e 'on run argv' \
      -e 'tell application (POSIX file (item 1 of argv) as alias) to quit' \
      -e 'end run' "$app" >/dev/null 2>&1; then
      warn "could not ask '$name' to quit; no files were moved"
      return 1
    fi
    if pgrep -x "$name" >/dev/null 2>&1; then
      warn "'$name' is still running; no files were moved"
      return 1
    fi
  fi

  local trash_dir
  trash_dir=$(mktemp -d "$HOME/.Trash/macsweep.XXXXXX") || die "could not create a unique folder in Trash"
  local target base n
  for p in "${items[@]}"; do
    base=$(basename "$p")
    target="$trash_dir/$base"
    n=1
    while [[ -e "$target" ]]; do
      target="$trash_dir/$base-$n"
      n=$(( n + 1 ))
    done
    if mv "$p" "$target" 2>/dev/null; then
      printf "  ${GRN}trashed${RST}  %s -> %s\n" "$p" "$target"
    else
      printf "  ${RED}failed${RST}   %s\n" "$p"
    fi
  done
  printf "Done. Items are grouped in %s; empty the Trash to reclaim the space.\n" "$trash_dir"
}

# ---------- large files ------------------------------------------------------

cmd_large() {
  local dir="${1:-$HOME}" mb="${2:-500}"
  [[ -d "$dir" ]] || die "not a directory: $dir"

  header "Largest folders in $dir"
  du -hd1 "$dir" 2>/dev/null | sort -rh | head -15

  header "Files over ${mb} MB in $dir"
  find "$dir" -type f -size +"${mb}"M -not -path "*/.Trash/*" -exec du -h {} + 2>/dev/null \
    | sort -rh | head -25
}

# ---------- startup ----------------------------------------------------------

cmd_startup() {
  header "Login items"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ */  /' || echo "  (could not read — grant Terminal Automation access)"

  local d
  for d in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
    header "$d"
    if [[ -d "$d" ]] && ls "$d"/*.plist >/dev/null 2>&1; then
      local plist found=0
      for plist in "$d"/*.plist; do
        [[ -e "$plist" ]] || continue
        printf "  %s\n" "${plist##*/}"
        found=1
      done
      (( found )) || echo "  (none)"
    fi
  done
}

# ---------- optimize ---------------------------------------------------------

cmd_optimize() {
  banner
  header "Optimize"
  if (( APPLY )); then sudo -v || die "sudo required"; fi

  run_cmd "flush DNS cache" bash -c 'sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
  run_cmd "purge inactive memory" sudo purge
  have qlmanage && run_cmd "reset QuickLook cache" qlmanage -r cache

  if (( LSREG )); then
    local ls=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    run_cmd "rebuild Launch Services DB (fixes Open With)" "$ls" -kill -r -domain local -domain system -domain user
  fi
  if (( SPOT )); then
    run_cmd "rebuild Spotlight index (slow, heavy CPU for a while)" sudo mdutil -E /
  fi
}

# ---------- updates ----------------------------------------------------------

cmd_updates() {
  header "macOS software updates"
  softwareupdate -l 2>&1
}

# ---------- main -------------------------------------------------------------

usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

main() {
  [[ "$(uname)" == "Darwin" ]] || die "this script is for macOS"

  local cmd="${1:-help}"; shift 2>/dev/null || true
  local args=() a
  for a in "$@"; do
    case "$a" in
      --apply|-a)       APPLY=1 ;;
      --yes|-y)         YES=1 ;;
      --docker-prune)   DOCKER_PRUNE=1 ;;
      --launchservices) LSREG=1 ;;
      --spotlight)      SPOT=1 ;;
      *)                args+=("$a") ;;
    esac
  done
  if (( ${#args[@]} )); then
    set -- "${args[@]}"
  else
    set --
  fi

  case "$cmd" in
    health)    cmd_health ;;
    clean)     cmd_clean ;;
    dev)       cmd_dev ;;
    all)       cmd_clean; TOTAL_KB=0; cmd_dev ;;
    uninstall) cmd_uninstall "$@" ;;
    large)     cmd_large "$@" ;;
    startup)   cmd_startup ;;
    optimize)  cmd_optimize ;;
    updates)   cmd_updates ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi