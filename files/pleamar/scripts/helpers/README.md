# Helper workers

pleamar's services carry audio, network, bluetooth, battery, media, tray, notifications, workspaces,
window and apps. The system monitor, weather, calendar and keyboard-layout views need data no
service has, so each view spawns one small stateless worker while it exists and kills it on close —
the same pattern as Vitreus' `vitreus-sysmon`. The workers live here, next to the scene harness, and
never run in the background on their own.

The protocol is **INTERFACES.md §7, frozen by PH1-T1**; this file repeats it for convenience and
adds the data keys each worker emits. Where this file and §7 disagree, §7 wins.

## Protocol

- **Transport.** The scene spawns a worker with
  `spawn(name, args, on_line, on_exit, { stdin = "open" })`; stdout and stdin are one JSON object
  per line (JSON Lines, UTF-8, `\n`, no embedded newlines). stderr is for humans only and is never
  part of the protocol.

- **Install names.** Workers are installed into `PATH` as `pleamar-<name>` and spawned by that bare
  name — never `sh -c`, never a path. A scene declares the ones it uses:
  `permissions { run: "pleamar-sysmon" }`.

  | file here     | installed name      | worker name in lines | topics                                                |
  | ------------- | ------------------- | -------------------- | ----------------------------------------------------- |
  | `sysmon.sh`   | `pleamar-sysmon`    | `sysmon`             | `sysmon`, `cpu`, `mem`, `swap`, `disk`, `gpu`, `temp` |
  | `weather.sh`  | `pleamar-weather`   | `weather`            | `weather`                                             |
  | `calendar.sh` | `pleamar-calendar`  | `calendar`           | `calendar`                                            |
  | `kbd.sh`      | `pleamar-kbdlayout` | `kbdlayout`          | `layout`                                              |

- **Handshake.** The first line a worker writes is
  `{"ok":true,"worker":"sysmon","version":1,"topics":["sysmon",…]}`. A scene that does not know
  `version` kills the worker; version 1 is §7. A worker that cannot start writes
  `{"ok":false,"worker":"sysmon","err":"…"}` and exits non-zero (no handshake, no half-working
  state).

- **Commands.** The scene writes JSON lines: `{"cmd":"sample"}`,
  `{"cmd":"subscribe","topic":"cpu","interval_ms":1000}`, `{"cmd":"unsubscribe","topic":"cpu"}`,
  `{"cmd":"set","interval_ms":250}`, `{"cmd":"stop"}`. Every command is answered with
  `{"ok":true,"ack":"…"}` or `{"ok":false,"err":"…"}`. An unknown `cmd` is an error line, not an
  exit. The workers additionally accept `{"cmd":"switch",…}` (kbd.sh) and `month` on
  `subscribe`/`sample`/`set` (calendar.sh), which §7 does not forbid: they are domain arguments, not
  a second protocol.

- **Samples.** `{"ok":true,"worker":"sysmon","topic":"cpu","t":1730000000123, "data":{…}}` — `t` is
  milliseconds since the epoch, `data` maps 1:1 onto the scene's model fields. **Errors keep the
  worker alive**: `{"ok":false,"worker":"weather","err":"open-meteo: HTTP 503","t":…}`; the scene
  keeps the last good sample and shows the text.

- **Cadence.** One line per sample, `interval_ms` ≥ 100 and at most ten lines a second; a line is at
  most 64 KiB. A topic that has nothing new to say still gets a heartbeat sample per interval.

- **Lifecycle.** One worker per view, started when the view opens and killed when it closes:
  `write(id, '{"cmd":"stop"}\n')` or `write(id)` for a clean finish, `kill(id, "term")` as the hard
  stop. **A closed stdin ends every worker** — none of them outlives its scene, and a `term` during
  an in-flight request kills that request first (weather and calendar kill their `curl` child), so
  the worker is gone within a few milliseconds. Cache files are the only things they write: one JSON
  document under `${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/helpers/` (weather, calendar), written
  atomically (temp file + rename); sysmon's counter baseline lives in a private temp file under
  `$TMPDIR` that is removed on exit.

- **Auto-subscription.** So a scene that only reads lines still gets data, each worker subscribes
  itself once before the first loop: sysmon `sysmon` at `--interval-ms` (1000), weather `weather` at
  600000, calendar `calendar` at 300000, kbdlayout `layout` at 5000. `unsubscribe` stops it;
  `subscribe` chooses the cadence.

### Consuming a worker (the §7 skeleton)

```lua
-- .plm:  permissions { run: "pleamar-sysmon" }
local id
local function on_line(line)
    local ok, msg = pcall(json.decode, line)
    if not ok or type(msg) ~= "table" then
        fact.worker.err = "sysmon: bad line"
        return
    end
    if msg.ok and msg.data then
        fact.worker.err = ""
        if msg.topic == "sysmon" then
            fact.cpu = (msg.data.cpu.percent or 0) / 100
            fact.ram = (msg.data.mem.percent or 0) / 100
        end
    elseif msg.err then
        fact.worker.err = tostring(msg.err)
    end
end
local function start()
    id = spawn("pleamar-sysmon", {}, on_line, nil, { stdin = "open" })
    write(id, '{"cmd":"subscribe","topic":"sysmon","interval_ms":1000}\n')
end
start()
-- on view close: if id then kill(id, "term") end
```

**Deprecated:** an earlier draft of this file described the sample lines as `{"ok":{…}}` with no
handshake or commands. §7 replaced that; scenes written against the draft must move to `msg.data`
(INTERFACES.md §7). The panels scene accepts both wire shapes, but the simple shape is not the
contract.

## The workers

### sysmon.sh — `pleamar-sysmon`

```
sysmon.sh [--interval-ms N] [--once] [--io-max-kibps N]
          [--gpu-path PATH | --no-gpu] [--temp-path PATH | --no-temp]
```

Reads procfs/sysfs only (`/proc/stat`, `/proc/meminfo`, `/proc/swaps`, `/proc/diskstats`, one
`gpu_busy_percent`, one hwmon CPU temperature input) and samples in one `awk` process per tick. The
`sysmon` topic carries the full sample, each subtopic carries its own object:

- `data.ts` epoch seconds (in `sysmon`);
- `cpu.percent` 0..100 from procfs tick deltas;
- `mem.used_gib`, `total_gib`, `percent` (MemTotal−MemAvailable);
- `swap.available`, `used_gib`, `total_gib`, `percent` (`/proc/swaps`);
- `disk.read_kibps`, `write_kibps`, `percent` (delta of diskstats sectors × 0.5 KiB/s; `percent`
  against `--io-max-kibps`, default 512000 ≈ 500 MiB/s);
- `gpu.percent` (largest-VRAM `gpu_busy_percent`) or `{"err":"…"}`;
- `temp.celsius`, `percent` (k10temp/coretemp/zenpower, else thermal zone 0; `percent = (C−30)/70`
  clamped) or `{"err":"…"}`.

Usage: subscribe to `sysmon` for one full sample per interval (the default), or to subtopics to draw
only what the view shows. A missing source is an `err` object inside `data`, never a dead worker.

### weather.sh — `pleamar-weather`

```
weather.sh [--city NAME] [--lat N --lon N] [--cache-file PATH] [--ttl SECONDS]
           [--force] [--interval-ms N] [--once] [--forecast-days N]
           [--timeout SECONDS] [--api-base URL] [--geocoding-base URL]
           [--wttr-base URL] [--no-fallback]
```

City from `--city` or `PLEAMAR_WEATHER_CITY`; coordinates from `--lat/--lon` (geocoding skipped) or
Open-Meteo's geocoding API (cached 24 h). `data`: `city`, `latitude`, `longitude`, `provider`
(`open-meteo` or `wttr.in`), `fetched_at`, `age_s`, `cached`,
`current{temp_c,weather_code,wind_ms, wind_dir_deg,is_day,humidity_pct,pressure_hpa}` and
`daily[{date,tmax_c,tmin_c,weather_code}]` (empty in the wttr.in fallback). The payload cache
(`$XDG_CACHE_HOME/pleamar/helpers/weather.json`, TTL `--ttl`, default 300 s) is served without
network; `--force` ignores a fresh one. Needs `curl` and `jq`; a failed provider is an `err` line
and the worker retries on the next sample. No API keys, no secrets.

### calendar.sh — `pleamar-calendar`

```
calendar.sh [--month YYYY-MM] [--country CC] [--cache-dir DIR]
            [--interval-ms N] [--once] [--holidays-base URL]
```

`khal list` for the month, day lines skipped and `{start-date}|{start-time}|{title}|{calendar}`
split into `events[{date,time,title,calendar}]`; `date` is normalized to ISO with GNU `date`. ISO
dates are tried first and retried as `%d.%m.%Y` when khal rejects them — this host's khal config
uses the locale format, and the legacy Quickshell helper passed ISO and silently got nothing. Month
navigation: `{"cmd":"sample","month":"2026-11"}` (or `set`/`subscribe` with `month`) re-asks khal
for another month and re-emits. `--country CC` adds `holidays[{date,name,name_en}]` from
date.nager.at (24 h file cache) and `holidays_error` carries a failed holiday fetch without failing
the events. Other `data` keys: `month`, `first`, `last`, `fetched_at`, `cached`, `age_s`. Event
results are cached for 120 s in `calendar-YYYY-MM.json` under `--cache-dir` (default
`$XDG_CACHE_HOME/pleamar/helpers`). khal missing is a start error
(`{"ok":false,"worker":"calendar","err":"khal not installed"}`, exit 1). Needs `jq` and `khal`;
`curl` only when `--country` asks for holidays.

### kbd.sh — `pleamar-kbdlayout`

```
kbd.sh [--once] [--socket PATH] [--interval-ms N] [switch [next|prev|DEVICE [next|prev]]]
```

`data`: `device` (main keyboard, else a non-virtual one), `main`, `index` (`active_layout_index`),
`keymap` (`active_keymap`), `code` (selected element of `layouts`), `layouts` (the `layout` field
split on commas), `submap` (`hyprctl submap`, `default`/`reset` reported as `""`) and `keyboards[]`
of `{name,main}`. Samples come from `hyprctl -j devices`, pushed by `.socket2.sock` events
(`activelayout` / `keyboard-layout` / `submap`, coalesced into one line per switch) plus the topic
heartbeat. Without a socket, or without `socat` to open it, the worker emits one error sample and
degrades to polling `hyprctl` instead of failing. Switching:
`{"cmd":"switch","device":"current","direction":"next"}` (or `"prev"`, or a device name), or the
plain line `switch [next|prev|DEVICE [next|prev]]`; both answer with an ack and a fresh sample.
`kbd.sh switch …` does the same from the command line and exits. Missing `hyprctl` is a start error
(exit 1). Needs `jq` and `hyprctl`; `socat` only for the live event stream (without it the worker
polls).
