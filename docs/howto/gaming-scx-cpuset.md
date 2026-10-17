# Gaming on trantor — SCX, cpuset and monitoring

## Games Stack Toggle

- Toggle the whole gaming stack:

  - `profiles.games.enable = false;` to disable Steam/Gamescope wrappers/MangoHud system‑wide.
  - Defaults to `true` to preserve current behavior.

- **Hybrid approach**: instead of kernel-level `isolcpus` (which blocks SCX schedulers), we use
  **SCX `scx_lavd`** (dual-CCD X3D-aware BPF scheduler) plus **cgroup cpuset**
  (`systemd-run -p AllowedCPUs=…`) to pin games to the V-Cache CCD.

- Host `trantor` pins games to V-Cache CCD cores `1-3,16-19` (96MB L3) via `systemd-run`. Kernel
  threads and IRQs stay on the housekeeping CCD `4-15,20-31` (32MB L3) via `irqaffinity=` and
  `kthread_cpus=` boot params.

- Transient scope runner: `game run` (Rust binary) launches any command in a user systemd scope and
  pins it to the gaming CPUs via `AllowedCPUs`.

- Gamescope helpers: `gamescope-pinned`, `gamescope-perf`, `gamescope-quality`, `gamescope-hdr`, and
  `gamescope-targetfps` wrap `game run`.

## Verifying SCX and affinity

- Check SCX scheduler: `cat /sys/kernel/sched_ext/state` → expect `enabled`, `ops` = `scx_lavd`
- Show CPU mask of current shell: `grep Cpus_allowed_list /proc/$$/status`
- Check a game run: `game run --dry-run -- /bin/true`

## Steam (per‑game Launch Options)

- Basic: `game run -- %command%`
- With Gamescope (fullscreen + VRR): `game run -- gamescope -f --adaptive-sync -- %command%`
- Override CPU set for a game: `GAME_PIN_CPUSET=0-3,16-19 game run -- %command%`
- Disable pinning: `game run --no-pin -- %command%`
- Disable GameMode: `game run --no-gamemode -- %command%`

## Non‑Steam games

- Run directly: `game run -- /path/to/game`
- With Gamescope presets:
  - Performance: `game scope --preset perf -- %command%`
  - Quality: `game scope --preset quality -- %command%`
  - HDR: `game scope --hdr -- %command%`

## Environment knobs

- `GAME_PIN_CPUSET`: CPU list or ranges (default `1-3,16-19`). Examples: `14,30` or `14-15,30-31`.
- `GAME_RUN_USE_GAMEMODE`: `1` (default) to run via `gamemoderun`, set `0` to disable.
- `GAMESCOPE_FLAGS`: extra flags appended to gamescope in `gamescope-pinned`.
- `GAMESCOPE_RATE`, `GAMESCOPE_OUT_W`, `GAMESCOPE_OUT_H`: override refresh and output size for
  gamescope wrappers.
- `TARGET_FPS`, `NATIVE_BASE_FPS`, `GAMESCOPE_AUTOSCALE`: control autoscaling in
  `gamescope-targetfps`.

Notes:

- Do not wrap the entire Steam client; prefer per‑game Launch Options to keep downloads/tooling on
  housekeeping CPUs.
- To change the default gaming cores system‑wide, adjust `gamingCpuSet` in
  `hosts/trantor/hardware.nix`.

## Gaming Recommendations

- 4K/240 Hz (VRR): use Gamescope with fullscreen and VRR to improve frame pacing on Wayland.

  - Typical: `game run -- gamescope -f --adaptive-sync -r 240 -- %command%`
  - If GPU‑limited, upscale: render lower, output native. Example 1440p→4K:
    `-w 2560 -h 1440 -W 3840 -H 2160 --fsr-sharpness 3`.

- HDR (AMD + Wayland): use the `gamescope-hdr` wrapper or add `--hdr-enabled` to Gamescope.

  - Require: monitor HDR on, recent kernel/Mesa, Gamescope with HDR enabled.
  - Some titles need in‑game HDR toggled after starting in HDR mode.

- Latency and stability:

  - Prefer per‑game CPU set: `GAME_PIN_CPUSET=1-3,16-19 game run -- %command%`. If a game spawns
    many threads, widen (e.g. `14-15,28-31`).
  - Keep VRR on: `--adaptive-sync`. If tearing or sync issues, test without it and/or cap FPS
    slightly below max (e.g. 237 on 240 Hz) via in‑game limiter or MangoHud.
  - Optional: test Gamescope `--rt` (realtime scheduling). If audio/input jitter occurs, remove it.

- Proton settings (per‑game, in Steam > Properties > Compatibility):

  - Proton‑GE often improves performance/compat (already installed). Switch back to Valve Proton if
    regressions.

- MangoHud overlay:

  - Toggle with `MANGOHUD=1`. FPS limit example:
    `MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game run -- %command%`.

- Mesa/AMD specifics:

  - Default Vulkan ICD is RADV (`AMD_VULKAN_ICD=RADV`). Override only for specific edge cases.
  - For some older GL titles, `MESA_GLTHREAD=true` may help.

- Troubleshooting stutter:

  - Ensure VRR is active (monitor OSD or `gamescope --verbose`).
  - Verify the game actually runs inside Gamescope (not an external launcher window).
  - Shader cache warm‑up can cause micro‑stutters during the first minutes.
  - If autosaves cause hitching, check disk load and disable background indexing.

- Useful commands:

  - Show current process CPU set: `grep Cpus_allowed_list /proc/<pid>/status`.
  - Reuse per‑game launch: `game run -- %command%` (Steam), `game run -- <path>` (outside Steam).

## Opinionated Presets (my own picks)

These presets are subjective and experimental — I came up with them myself. Use them as starting
points and tweak for your rig/game.

- Competitive FPS (lowest latency, 240 Hz VRR):

  - Steam Launch Options:
    - `GAME_PIN_CPUSET=1-3,16-19 MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game run -- gamescope -f --adaptive-sync -r 240 -- %command%`
  - Notes: cap below max refresh (237/240) for steadier frametimes; try adding `--rt` to Gamescope
    if stability is OK; turn off in‑game V‑Sync.

- Cinematic Single‑Player (quality first, steady 120 FPS feel):

  - If native 4K sustainable: `game run -- gamescope -f --adaptive-sync -r 120 -- %command%`
  - If GPU‑bound: 1800p→4K upscale:
    `game run -- gamescope -f --adaptive-sync -r 120 -w 3200 -h 1800 -W 3840 -H 2160 --fsr-sharpness 3 -- %command%`
  - Notes: on 240 Hz panel 120 FPS also feels smooth with VRR and frees headroom for HDR/RT.

- Heavy DX12/Open‑World (e.g., RT heavy):

  - Start conservative: `TARGET_FPS=110 game run -- gamescope -f --adaptive-sync -- %command%`
  - Optional RADV toggles (may change with Mesa versions): `RADV_PERFTEST=gpl shadercache` — only if
    you know what you're doing.

- Strategy/Sim With Many Worker Threads:

  - Widen CPU set for the game: `GAME_PIN_CPUSET=12-15,28-31 game run -- %command%`
  - If stutters from background tasks — keep Gamescope and MangoHud, but drop `--rt`.

- Emulators / Older GL Titles:

  - `MESA_GLTHREAD=true game run -- %command%`
  - For strict frame pacing, prefer integer scale in Gamescope or cap FPS to native rate divisors.

- HDR Titles:

  - `game run -- gamescope --hdr-enabled -f --adaptive-sync -- %command%`
  - In‑game HDR must be toggled; verify monitor HDR OSD and Gamescope logs.

Tuning tips:

- If input lag grows, remove `--rt` and lower FPS cap slightly.
- If GPU sits at 99% with spikes, reduce render resolution (`-w/-h`) or apply in‑game upscalers
  (FSR/DLSS/XeSS) while keeping Gamescope output at native.
- If CPU spikes, reduce background activity, or allow more CPUs in `GAME_PIN_CPUSET`.

## Lightweight Monitoring (Gaming PC)

- Netdata (local, very light):

  - Enable per-host: set `monitoring.netdata.enable = true;` (see
    hosts/trantor/services/policy.nix).
  - Opens a local UI at `http://127.0.0.1:19999` with CPU/GPU/sensors/disks/net.
  - Service is de‑prioritized (nice/CPU/IO weights) to minimize impact.
  - Extend via `services.netdata.config` if you need extra collectors.

- Sysstat history (ultra‑light):

  - Enable per-host: `monitoring.sysstat.enable = true;`.
  - View later: `sar`, `iostat`, `mpstat`, `pidstat`.

- In‑game overlay (already included):

  - Use MangoHud: run games with `MANGOHUD=1`.
  - Toggle logging in-game: `Shift+F2` (CSV saved under `$XDG_DATA_HOME/MangoHud` by default).

- VictoriaMetrics (optional, if you want graphs without Grafana):

  - Suggested stack: `vmagent -> VictoriaMetrics single -> vmui`.
  - Very low RAM/CPU at 10–15 s scrape and 7–14 days retention.
  - Not enabled here by default; can be added later as a separate module if desired.
