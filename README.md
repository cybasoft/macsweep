# macsweep

`macsweep` is a Bash utility for checking Mac health, reviewing disk usage, and cleaning selected user and developer data. It is intended for macOS.

## Safety

Commands that can make changes are dry runs by default. Add `--apply` to execute them. Read the preview before applying it, especially for `dev`, `all`, and `uninstall`.

The `clean` command never automatically deletes `~/Downloads`, iOS device backups, or Xcode Archives; it reports those for manual review. It can clear user caches, logs, Mail attachment downloads, and Trash unless you skip those targets. Close apps before clearing caches or logs when practical.

Cleanup sizes are estimates. The `clean` and `dev` summaries count directory cleanup only; savings from Homebrew, pnpm, Docker, and simulator commands are not included. Freed space reported by a cleanup may differ from the change in macOS available storage, for example because of open files or local snapshots.

## Install

From this directory:

```bash
mkdir -p ~/bin
cp macsweep.sh ~/bin/macsweep
chmod +x ~/bin/macsweep
```

Ensure `~/bin` is in your `PATH`, then run `macsweep`. Alternatively, run the script directly with `bash macsweep.sh`.

## Usage

```text
macsweep <command> [options]

Commands:
  health                 Show disk, memory, CPU, battery, and security status
  clean                  Preview or clear selected user cleanup targets
  dev                    Preview or clear developer caches and tool data
  all                    Run clean, then dev
  uninstall <App Name>   Find an app and matching leftovers; move them to Trash
  large [dir] [minMB]    Find large files and top-level folders
  startup                List login items and launch agent/daemon plist files
  optimize               Run maintenance commands
  updates                List available macOS software updates
  help                   Show command help

Options:
  --apply, -a            Execute changes (default: preview only)
  --yes, -y              Skip the move-to-Trash confirmation for uninstall
  --docker-prune         dev/all: prune Docker data when explicitly requested
  --launchservices       Also rebuild the Launch Services database (optimize)
  --spotlight            Also erase and rebuild the Spotlight index (optimize)
```

Options can appear after the command or its arguments. Quote app names or paths containing spaces.

## Clean Targets

When run from an interactive terminal, `clean` asks which targets to skip. Enter numbers separated by spaces or commas; press Enter to skip none.

| Number | Target | Behavior |
| --- | --- | --- |
| 1 | `~/Library/Caches` | Clears the contents of the user caches directory |
| 2 | `~/Library/Logs` | Clears the contents of the user logs directory |
| 3 | Mail attachment downloads | Clears the Mail downloads directory, if present |
| 4 | `~/.Trash` | Clears the contents of Trash; Full Disk Access may be needed |

`~/Downloads` is report-only and is never an automatic cleanup target. In a non-interactive run, the skip prompt is not shown, so no targets are skipped automatically. The `dev` command has its own fixed targets and does not use these numbers.

## Commands

### `health`

Reports macOS version, uptime, root disk usage, available SMART/SSD details, local Time Machine snapshot count, memory pressure, swap use, top CPU and memory processes, battery details when available, SIP, FileVault, Gatekeeper, firewall status, and outdated Homebrew packages when Homebrew is installed.

### `clean`

Previews or clears the four numbered targets above. Also reports iOS device backups, Downloads, Xcode Archives, and local Time Machine snapshots for manual review. Use the skip prompt if any automatic target should be left untouched.

### `dev`

Previews or runs cleanup for Xcode DerivedData and iOS DeviceSupport, unavailable simulator devices, npm and Composer caches, Gradle caches, the pnpm store, and Homebrew cleanup when the relevant tools are installed. Docker storage is reported but not pruned by default. Pass `--docker-prune` to run `docker system prune -f`, which removes stopped containers and unused Docker data; it does not request volume removal. Some cleaned data may need to be downloaded or rebuilt later.

### `all`

Runs `clean` followed by `dev`. In an interactive terminal, answer the `clean` skip prompt before the developer cleanup preview. Apply mode executes both commands, so review both sets of targets.

### `uninstall <App Name>`

Looks for `<App Name>.app` in `/Applications` and `~/Applications`, then lists exact bundle-ID matches and matching preference plist files under common locations in `~/Library`. It does not move system-wide data from `/Library`; related system helpers may need separate removal. Other app data is left untouched. With `--apply`, the script asks before moving matches into a unique folder under `~/.Trash`. If the app appears to be running, it separately asks whether to request a graceful quit; declining or failing to quit stops the move. `--yes` skips only the move confirmation, not the quit prompt.

### `large [dir] [minMB]`

Lists the largest immediate subfolders and files over the size threshold. Defaults to `$HOME` and 500 MB. The `.Trash` directory is excluded from the large-file list.

### `startup`

Lists login item names and plist filenames from the user and system LaunchAgents and system LaunchDaemons directories. macOS may require Terminal Automation permission to read login items.

### `optimize`

With `--apply`, flushes DNS caches, runs `purge`, and resets the QuickLook cache when available. These do not delete personal files. `--launchservices` also rebuilds the Launch Services database; `--spotlight` erases and rebuilds the Spotlight index and can cause heavy disk and CPU activity. Some operations require administrator privileges.

### `updates`

Lists available macOS software updates; it does not install them.

## Examples

```bash
macsweep health
macsweep clean                 # preview; choose targets to skip
macsweep clean --apply         # apply after choosing targets to skip
macsweep dev --apply
macsweep dev --docker-prune --apply
macsweep all                   # preview clean and developer cleanup
macsweep all --apply
macsweep uninstall "Slack" --apply
macsweep large ~/Downloads 200
macsweep optimize --apply --launchservices
```

## License

macsweep is licensed under the [MIT License](LICENSE).

## Checks

Run `bash -n macsweep.sh`, `shellcheck macsweep.sh`, and `bash tests/safety.sh` before release. The safety tests require macOS and use a temporary home directory; Docker and Homebrew are mocked, and uninstall is only previewed.
