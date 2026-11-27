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

## Homebrew

```bash
brew tap cybasoft/tap
brew install macsweep
```


## Usage

```text
macsweep <command> [options]

Core commands:
  system health             Show disk, memory, CPU, battery, and security status
  system optimize           Run maintenance commands
  system updates            List available macOS software updates
  clean system              Preview or clear selected user cleanup targets
  clean dev                 Preview or clear developer caches and tool data
  clean large [dir] [MB]    Find large files and top-level folders
  apps uninstall <App Name> Find an app and matching leftovers; move them to Trash
  startup                   List login items and launch agent/daemon plist files

Optional modules:
  ports [port]              Inspect listeners and processes
  network                   Run network diagnostics
  doctor                    Diagnose development environment setup
  files <subcommand>        Inspect symlinks, permissions, attributes, and metadata
  json <subcommand>         Validate, format, compare, and query JSON

Management:
  list                      List installed and available modules
  install <module>          Install an optional module
  uninstall <module>        Remove an optional module
  update [module]           Update an optional module or all installed modules

Options:
  --apply, -a            Execute changes (default: preview only)
  --yes, -y              Skip the move-to-Trash confirmation for uninstall
  --non-interactive      Never prompt; missing modules return an install instruction
  --docker-prune         dev/all: prune Docker data when explicitly requested
  --launchservices       Also rebuild the Launch Services database (optimize)
  --spotlight            Also erase and rebuild the Spotlight index (optimize)
```

Options can appear after the command or its arguments. Quote app names or paths containing spaces.

The legacy commands `health`, `clean`, `dev`, `all`, `uninstall`, `large`, `startup`, `optimize`, and `updates` remain temporary compatibility aliases.

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

## Toolbox modules

Optional modules are not installed with the core CLI.

| Module | Command | Purpose |
| --- | --- | --- |
| PortSweep | `macsweep ports [port]` | Listen on TCP ports and identify processes |
| NetSweep | `macsweep network` | Inspect DNS, connectivity, latency, and configuration |
| DevSweep | `macsweep doctor` | Diagnose PATH, shell, language, Homebrew, Git, and Docker setup |
| FileSweep | `macsweep files <subcommand> [path]` | Inspect symlinks, permissions, hidden files, metadata, and attributes |
| JSONSweep | `macsweep json <subcommand> <file>` | Pretty-print, validate, compare, and query JSON |

Module commands display an installation prompt in an interactive terminal. Non-interactive runs never prompt and exit with a missing-module instruction. Modules are stored under `~/.local/share/macsweep/modules/`; cache data is stored under `~/.local/share/macsweep/cache/`.

```bash
macsweep list
macsweep install ports
macsweep install ports --version 1.0.0
macsweep uninstall ports
macsweep update
macsweep update ports
```

Modules come only from the static registry in `modules.tsv`. Installer downloads are limited to pinned Cybasoft GitHub release paths and verified with a SHA-256 checksum before installation. Downloads are staged in a temporary directory and modules are never overwritten silently.

## Examples

```bash
macsweep system health
macsweep clean system          # preview; choose targets to skip
macsweep clean system --apply  # apply after choosing targets to skip
macsweep clean dev --apply
macsweep clean dev --docker-prune --apply
macsweep clean large ~/Downloads 200
macsweep apps uninstall "Slack" --apply
macsweep system optimize --apply --launchservices

macsweep ports
macsweep network
macsweep doctor
macsweep files symlinks ~/Projects
macsweep json pretty file.json
```

## License

macsweep is licensed under the [MIT License](LICENSE).

## Checks

Run `bash -n macsweep.sh core/*.sh tools/*/module.sh`, `shellcheck macsweep.sh core/*.sh tools/*/module.sh`, and `bash tests/safety.sh`, `bash tests/architecture.sh`, and `bash tests/install.sh` before release. The tests require macOS and use a temporary home directory; Docker, Homebrew, and `curl` are mocked, and uninstall is only previewed.
