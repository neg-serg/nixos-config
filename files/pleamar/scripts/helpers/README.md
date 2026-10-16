# Helper workers

pleamar's services carry audio, network, bluetooth, battery, media, tray, notifications, workspaces,
window and apps. The system monitor, weather, calendar and keyboard-layout views need data no
service has, so each view spawns one small stateless worker while it exists and kills it on close —
the same pattern as Vitreus' `vitreus-sysmon`. The workers live here, next to the scene harness, and
never run in the background on their own.

## Protocol

- **stdout is the channel**: one JSON object per line, flushed after each line. Nothing else is ever
  written to stdout.
- **Two shapes only**: `{"ok": <payload>}` on success and `{"err": "<text>"}` on failure. No bare
  values, no multi-line objects, no extra keys next to `ok`/`err`.
- **Keys are stable**: a payload key always means the same thing, and only its type may change to an
  error object when exactly that one source is missing (`"gpu": {"err": "cannot read …"}`). Keys may
  be added in a release; they are never renamed or repurposed. Scenes must tolerate unknown keys and
  null values.
- **stderr is for people**: diagnostics and khal/hyprctl complaints, never data. A scene may forward
  stderr to its log.
- **stdin is for commands**, one per line, and only where a worker documents it (`kbd.sh` reads
  `switch …`). Spawn with `{ stdin = "open" }` to send them; without it workers do not read stdin.
  An end of stdin is not fatal.
- **Exit codes**: `0` means the worker finished its job, including "I wrote an `err` line and
  stopped"; `2` means a usage error, reported on stderr before any stdout line; `1` is reserved for
  a worker that dies on its own (an unreadable `/proc` file in `sysmon.sh`). `SIGTERM`/`SIGPIPE`
  from the scene are normal and must leave nothing behind.
- **Lifecycle**: `spawn(…)` when the view opens, `kill(id, "term")` when it closes. No worker
  detaches, daemonizes or survives its stdout: a closing pipe ends them on the next write
  (`SIGPIPE`).
- **Cache files**: `weather.sh` and `calendar.sh` may write one JSON file under
  `${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/helpers/` (or the path given on the command line). They
  write it atomically (temp file + rename) and never touch anything else.

### Spawning from a scene

Workers are plain bash scripts; spawn them through an interpreter so their repository location does
not matter, and declare the command the scene runs:

```lua
-- .plm:  permissions { run: "bash" }
local id = spawn("bash", { HELPER_DIR .. "/sysmon.sh", "--interval", "1" },
    function(line)
        local ok, d = pcall(json.decode, line)
        if ok and d.ok then
            fact.cpu = (d.ok.cpu_percent or 0) / 100
            fact.ram = ((d.ok.mem or {}).percent or 0) / 100
        elseif ok then
            log("sysmon: " .. tostring(d.err))
        end
    end,
    function(_, code) if code ~= 0 then log("sysmon ended: " .. code) end end)
-- on view close: kill(id, "term")
```

`HELPER_DIR` is wherever the deployment puts these scripts (nix store path or
`~/.local/share/pleamar/helpers`). A worker may also be spawned as an executable by its path when
that path is declared in `permissions { run: … }` — the permission string must match the spawned
command exactly.

## The workers

| worker        | shape                                                 | one line means                                                             |
| ------------- | ----------------------------------------------------- | -------------------------------------------------------------------------- |
| `sysmon.sh`   | `{"ok": {…}}` every `--interval` seconds (default 1)  | one sample: cpu %, ram/swap, disk rates, gpu %, cpu temperature            |
| `weather.sh`  | `{"ok": {…}}` once (or every interval with `--watch`) | current weather + short daily forecast, from Open-Meteo (wttr.in fallback) |
| `calendar.sh` | `{"ok": {…}}` once (or with `--watch`)                | one month of khal events, plus optional public holidays                    |
| `kbd.sh`      | `{"ok": {…}}` on start and on each Hyprland event     | keyboard device, layout and submap; `switch` on stdin switches layout      |

### sysmon.sh

```
sysmon.sh [--interval SECONDS] [--once] [--io-max-kibps N]
          [--gpu-path PATH | --no-gpu] [--temp-path PATH | --no-temp]
```

Payload keys: `ts` (epoch), `interval_s`, `cpu_percent` (0..100, delta over procfs ticks),
`mem{used_gib,total_gib,percent}` (MemTotal−MemAvailable),
`swap{available,used_gib,total_gib,percent}` (`/proc/swaps`), `disk{read_kibps,write_kibps,percent}`
(delta of `/proc/diskstats` sectors × 0.5 KiB/s; `percent` against `--io-max-kibps`, default 512000
≈ 500 MiB/s), `gpu{percent}` (largest-VRAM `gpu_busy_percent`), `temp{celsius,percent}`
(k10temp/coretemp/zenpower `temp1_input`, else thermal zone 0; percent = `(C−30)/70` clamped). A
source that is absent is `{"err": "…"}` in its own key; an unreadable `/proc/stat` or
`/proc/meminfo` is a top-level `{"err": …}` and exit 1 (never happens on Linux). Discovery runs
once; `--gpu-path`, `--temp-path`, `--no-gpu`, `--no-temp` override it. Reads procfs/sysfs only, no
subprocess except the one `sleep` that paces samples.

### weather.sh

```
weather.sh [--city NAME] [--lat N --lon N] [--cache-file PATH] [--ttl SECONDS]
           [--watch] [--interval SECONDS] [--force] [--forecast-days N]
           [--timeout SECONDS] [--api-base URL] [--geocoding-base URL]
           [--no-fallback]
```

City comes from `--city` or `PLEAMAR_WEATHER_CITY`, coordinates from `--lat/--lon` (geocoding
skipped) or Open-Meteo's geocoding API. Payload keys: `city`, `latitude`, `longitude`, `provider`
(`open-meteo` or `wttr.in`), `fetched_at` (epoch), `age_s`, `cached`,
`current{temp_c,weather_code, wind_ms,wind_dir_deg,is_day,humidity_pct,pressure_hpa}` and `daily[]`
of `{date,tmax_c,tmin_c,weather_code}` (empty for the wttr.in fallback). Cache: one JSON file
(default `$XDG_CACHE_HOME/pleamar/helpers/weather.json`) holding coords and payload with timestamps;
`--ttl` (default 300 s) serves it without network, `--force` skips it. Geocoding is cached for 24 h.
Needs `curl` and `jq`; a missing tool, empty city or failed provider is an `err` line.

### calendar.sh

```
calendar.sh [--month YYYY-MM] [--country CC] [--cache-dir DIR]
            [--watch] [--interval SECONDS]
```

`khal list` for the month (default: the current one), day lines skipped and
`{start-date}|{start-time}|{title}|{calendar}` split into `events[{date,time,title,calendar}]`;
`date` is normalized to ISO with GNU `date`. ISO dates are tried first and, because khal parses
dates with the locale format from its own config, the run is retried as `%d.%m.%Y` when khal rejects
them — this host's khal needs the retry. `--country CC` adds `holidays[{date,name,name_en}]` from
date.nager.at (24 h file cache) and `holidays_error` carries a failed holiday fetch without failing
the events. Other keys: `month`, `first`, `last`, `fetched_at`, `cached`. Event results are cached
for 120 s in `calendar-YYYY-MM.json` under `--cache-dir` (default
`$XDG_CACHE_HOME/pleamar/helpers`). khal missing is `{"err": "khal not installed"}`.

### kbd.sh

```
kbd.sh [--once] [--socket PATH] [--interval SECONDS] [switch [next|prev|DEVICE]]
```

Prints the status once and then streams a fresh status line for every
`activelayout`/`keyboard-layout`/`submap` event on Hyprland's `.socket2.sock` (`socat` is used to
open the socket; without a socket, or without socat, it degrades to polling `hyprctl -j devices`
every `--interval` seconds instead of failing). Payload keys: `device` (main keyboard, else a
non-virtual one), `main`, `index`, `keymap` (`active_keymap`), `code` (selected element of
`layouts`), `layouts` (the `layout` field split on commas), `submap` (`hyprctl submap`,
`default`/`reset` reported as `""`) and `keyboards[]` of `{name,main}`. Stdin command: `switch`,
`switch next`, `switch prev`, `switch DEVICE [next|prev]`; each runs
`hyprctl switchxkblayout DEVICE next|prev` and answers with the new status line. `switch` as a CLI
argument does the same and exits. Missing `hyprctl` is `{"err": "hyprctl not found"}`; a missing
Hyprland socket is tolerated as described above.
