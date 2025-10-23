# Interesting stuff

```

# Nextcloud: pin major version (package)
{ pkgs, ... }: {
  # Use a specific Nextcloud derivation (e.g., 31)
  servicesProfiles.nextcloud.package = pkgs.nextcloud31;
  # Or point to a flake-provided package
  # servicesProfiles.nextcloud.package = inputs.my-nextcloud.packages.${system}.nextcloud;
}
```
nixtheplanet.url = "github:matthewcroughan/NixThePlanet";
```

```
nixos-generators
```

## Evaluation Noise Policy

- No evaluation-time warnings or traces. Keep builds and switches quiet.
- Do not use `warnings = [ ... ]`, `builtins.trace`, or `lib.warn` in modules.
- If a package/feature is unavailable, silently skip or guard with a flag. Document behavior in module docs/README instead of emitting warnings.
- Use assertions only for truly fatal misconfigurations that would break the system, and phrase them concisely.

## Hyprland: Single Source of Truth and Updates

- Source of truth: `inputs.hyprland` is pinned to a stable tag (see `flake.nix`).
- Dependencies are kept in lockstep via `follows`:
  - `hyprland-protocols` → `hyprland/hyprland-protocols`
  - `hyprland-qtutils` → `hyprland/hyprland-qtutils`
  - `hyprland-qt-support` → `hyprland/hyprland-qtutils/hyprland-qt-support`
  - `xdg-desktop-portal-hyprland` → `hyprland/xdph`
- Usage in modules:
  - `programs.hyprland.package = inputs.hyprland.packages.<system>.hyprland`
  - `programs.hyprland.portalPackage = inputs.xdg-desktop-portal-hyprland.packages.<system>.xdg-desktop-portal-hyprland`
  - Do not add `xdg-desktop-portal-hyprland` to `xdg.portal.extraPortals` (to avoid duplicate unit) — it comes via `portalPackage`.

How to update Hyprland (and related deps):

1) Change `inputs.hyprland.url` in `flake.nix` (e.g., to a new release tag).
2) Update the lock: `nix flake lock --update-input hyprland`.
3) Rebuild the system: `nh os switch /etc/nixos`.

Auto‑update (optional): if `system.autoUpgrade` with flakes is enabled, you can add `--update-input hyprland` to automatically pull newer Hyprland. We typically update it manually to keep compatibility under control.

## Roles & Profiles

- Roles: enable bundles via `modules/roles/{workstation,homelab,media}.nix`.
  - `roles.workstation.enable = true;` → desktop defaults (performance profile, SSH, Avahi, Syncthing).
  - `roles.homelab.enable = true;` → self‑hosting defaults (security profile, DNS, SSH, Syncthing, MPD, Navidrome, Wakapi, Nextcloud).
  - `roles.media.enable = true;` → media servers (Jellyfin, Navidrome, MPD, Avahi, SSH).
- Profiles: feature flags under `modules/system/profiles/`:
  - `profiles.performance.enable` and `profiles.security.enable` are toggled by roles; override per host if needed.
- Service profiles: toggle per‑service via `profiles.services.<name>.enable` (alias to `servicesProfiles.<name>.enable`).
  - Roles set `mkDefault true`; hosts can disable with plain `false` (no mkForce needed).
- Host‑specific config: keep concrete settings under `hosts/<host>/*.nix`.
  - Examples: Syncthing devices/folders, Nextcloud domain/proxy, NIC names, local DNS rewrites.

Example (host):

```nix
{ lib, ... }: {
  roles = {
    workstation.enable = true;
    homelab.enable = true;
  };

  # Disable heavy services for VMs or minimal builds
  profiles.services = {
    nextcloud.enable = false;
    adguardhome.enable = false;
  };

  # Host‑specific Syncthing (devices/folders)
  services.syncthing = {
    overrideDevices = true;
    overrideFolders = true;
    settings.devices."phone" = { id = "AAAA-BBBB-..."; };
  };
}
```

Example (media role):

```nix
{ lib, ... }: {
  roles.media.enable = true;

  # This role enables Jellyfin, Navidrome, MPD, Avahi, SSH by default.
  # Per-host overrides (e.g., disable Jellyfin on this machine):
  profiles.services.jellyfin.enable = false;

  # Media server host-specific tweaks can live here as well (paths, ports, etc.).
}
```

Service override examples

```nix
# Navidrome: change library path and port
{
  services.navidrome.settings = {
    MusicFolder = "/srv/media/music";
    Port = 4533;
  };
}

# MPD: change music dir/port and append an extra output
{ lib, ... }: {
  services.mpd = {
    musicDirectory = "/srv/media/music";
    network.port = 6601;
    # Append to the module's extraConfig (types.lines supports mkAfter)
    extraConfig = lib.mkAfter ''
      audio_output {
        type "alsa"
        name "USB DAC"
        device "hw:USB"
      }
    '';
  };
}
```

## Kernel Modules Layout

- params: kernel cmdline and packaging (modules/params) in `modules/system/kernel/params.nix`.
- sysctl: network/security sysctls in `modules/system/kernel/sysctl.nix`.
- patches-amd: `boot.kernelPatches` with `structuredExtraConfig` for AMD in `modules/system/kernel/patches-amd.nix`.
- Feature toggles: tune via `profiles.performance.*` and `profiles.security.*`; params derive from these.

## Cooling / Fan Control (quiet profile)

- Enable sensors and a quiet fan curve via `hardware.cooling.*` (module: `modules/hardware/cooling.nix`).
- For typical ASUS/Nuvoton motherboards, the module loads `nct6775` and generates `/etc/fancontrol` on boot.
- Optional: include AMD GPU fan in the same profile (`hardware.cooling.gpuFancontrol.enable = true;`).

Example (quiet, safe defaults):

```nix
{
  hardware.cooling = {
    enable = true;
    autoFancontrol.enable = true;  # generate conservative quiet curve
    gpuFancontrol.enable = true;   # include AMDGPU pwm1 with a quiet curve
    # Optional tweaks (defaults shown):
    # autoFancontrol.minTemp = 35;  # °C to start ramping
    # autoFancontrol.maxTemp = 75;  # °C for max fan speed
    # autoFancontrol.minPwm  = 70;  # 0–255, avoid stall while quiet
    # autoFancontrol.maxPwm  = 255; # 0–255
    # autoFancontrol.hysteresis = 3;  # °C
    # autoFancontrol.interval  = 2;   # seconds
  };
}
```

- Notes:
- The generator uses CPU temperature (`k10temp`) to drive all motherboard PWM channels (nct6775).
- If `gpuFancontrol.enable = true`, GPU fan (amdgpu pwm1) is driven by GPU temp (prefer junction sensor when available).
- If `/etc/fancontrol` already exists, it is backed up once to `/etc/fancontrol.backup` and replaced with a symlink to `/etc/fancontrol.auto`.
- GPU fans remain managed by the GPU driver; only motherboard PWM headers are targeted.
  - Exception: when `gpuFancontrol.enable = true`, we switch `pwm1_enable` to manual and fancontrol takes over.

## GPU CoreCtrl (Undervolt/Power‑Limit)

- Optional capability (disabled by default): `hardware.gpu.corectrl.enable = false;`
- When enabled, installs CoreCtrl and a polkit rule allowing members of a chosen group (default `wheel`) to use the CoreCtrl helper.
- Optional: set `hardware.gpu.corectrl.ppfeaturemask = "0xffffffff";` to unlock extended OC/UV controls on some AMD GPUs.

Example:
```nix
{
  hardware.gpu.corectrl = {
    enable = true;            # off by default
    group = "wheel";          # who can tune
    # ppfeaturemask = "0xffffffff"; # optional, only if needed for your GPU
  };
}
```

## RNNoise Virtual Mic (PipeWire)

- Provides a virtual microphone with RNNoise noise suppression via PipeWire filter-chain.
- Global default is enabled; per-host you can disable it explicitly.

Example:

```nix
{
  # Globally (module default is true)
  hardware.audio.rnnoise.enable = true;

  # Per-host override (e.g., hosts/telfir/services.nix)
  hardware.audio.rnnoise.enable = false;
}
```

Notes:
- A user service auto-selects the RNNoise source as the default input on login when enabled.
- You can still manually choose sources in your desktop environment if you prefer.

Russian version: see README.ru.md.



## AutoFDO (sample-based PGO)

Enable tooling and optional compiler wrappers:

```nix
{ lib, ... }: {
  # Install AutoFDO tools
  dev.gcc.autofdo.enable = true;

  # Provide GCC wrappers `gcc-afdo` and `g++-afdo`
  # that append -fauto-profile=<path>
  dev.gcc.autofdo.gccProfile = "/var/lib/afdo/myprofile.afdo";

  # Provide Clang wrappers `clang-afdo` and `clang++-afdo`
  # that append -fprofile-sample-use=<path>
  # dev.gcc.autofdo.clangProfile = "/var/lib/afdo/llvm.prof";
}
```

Usage:

- GCC: `gcc-afdo main.c -O3 -o app`
- Clang: `clang-afdo main.c -O3 -o app`


## Commit message policy and local hook

- Subject style: `[scope] short description` in English, ASCII only.
- Exceptions: Git-generated subjects like `Merge ...`, `Revert ...`, and `WIP:` are allowed.

Enable the repo hook locally:

```
git config core.hooksPath .githooks
```

The hook rejects commit messages that contain non‑ASCII characters or do not start with a bracketed scope.

Additionally, a Markdown language policy is enforced:
- English docs live in `*.md`.
- Russian docs must live in `*.ru.md`.
The pre-commit hook and CI check `lint-md-lang` will fail if Cyrillic is present in non-`*.ru.md` files.

## Module Pattern & Option Helpers

- This repo favors a consistent module pattern and provides helpers in `lib/opts.nix`.
- See aggregated options and module examples in generated docs under flake outputs.

## Gaming: Per‑Game CPU Isolation & Launchers

### Games Stack Toggle

- Toggle the whole gaming stack:
  - `profiles.games.enable = false;` to disable Steam/Gamescope wrappers/MangoHud system‑wide.
  - Defaults to `true` to preserve current behavior.

- Isolated CPUs: host `telfir` reserves cores `14,15,30,31` for low‑latency gaming. System services are kept on housekeeping CPUs.
- Transient scope runner: `game-run` launches any command in a user systemd scope and pins it to the isolated CPUs via `game-affinity-exec`.
- Gamescope helpers: `gamescope-pinned`, `gamescope-perf`, `gamescope-quality`, `gamescope-hdr`, and `gamescope-targetfps` wrap `game-run`.

### Steam (per‑game Launch Options)

- Basic: `game-run %command%`
- With Gamescope (fullscreen + VRR): `game-run gamescope -f --adaptive-sync -- %command%`
- Override CPU set for a game: `GAME_PIN_CPUSET=14,15,30,31 game-run %command%`
- Disable GameMode for a game: `GAME_RUN_USE_GAMEMODE=0 game-run %command%`

### Non‑Steam games

- Run directly: `game-run /path/to/game`
- With Gamescope presets:
  - Performance: `gamescope-perf <game | command-with-args>`
  - Quality: `gamescope-quality <game | command-with-args>`
  - HDR: `gamescope-hdr <game | command-with-args>`
  - Target FPS autoscale: `TARGET_FPS=120 gamescope-targetfps <cmd>`

### Environment knobs

- `GAME_PIN_CPUSET`: CPU list or ranges (default `14,15,30,31`). Examples: `14,30` or `14-15,30-31`.
- `GAME_RUN_USE_GAMEMODE`: `1` (default) to run via `gamemoderun`, set `0` to disable.
- `GAMESCOPE_FLAGS`: extra flags appended to gamescope in `gamescope-pinned`.
- `GAMESCOPE_RATE`, `GAMESCOPE_OUT_W`, `GAMESCOPE_OUT_H`: override refresh and output size for gamescope wrappers.
- `TARGET_FPS`, `NATIVE_BASE_FPS`, `GAMESCOPE_AUTOSCALE`: control autoscaling in `gamescope-targetfps`.

### Verifying affinity and scope

- Show CPU mask of current shell: `grep Cpus_allowed_list /proc/$$/status`
- Check a game run: `game-run bash -lc 'grep Cpus_allowed_list /proc/$$/status; sleep 1'`

## Main User (single source of truth)

- Configure the primary account via `users.main.*` in modules:
  - `users.main.name`: login name (default `neg`).
  - `users.main.uid` / `users.main.gid`: IDs for user/group (default `1000`).
  - `users.main.group`: primary group name (defaults to `users.main.name`).
  - `users.main.description`, `users.main.opensshAuthorizedKeys`, `users.main.hashedPassword`.
- Modules use this instead of hardcoded names/IDs:
  - MPD runs as `users.main.name` and sets `XDG_RUNTIME_DIR` from `users.main.uid`.
  - Syncthing runs as `users.main.name`.
  - Filesystem bind mounts under the main home instead of `/home/neg/...`.
  - Extra groups and PAM limits reference the main user/group.
- Inspect transient scope: `systemctl --user list-units 'app-*scope' --no-pager`

Notes:
- Do not wrap the entire Steam client; prefer per‑game Launch Options to keep downloads/tooling on housekeeping CPUs.
- To change the default isolated cores system‑wide, set `GAME_PIN_CPUSET` in the environment or adjust host CPU isolation in `modules/hardware/host/telfir.nix`.

## Gaming Recommendations

- 4K/240 Hz (VRR): use Gamescope with fullscreen and VRR to improve frame pacing on Wayland.
  - Typical: `game-run gamescope -f --adaptive-sync -r 240 -- %command%`
  - If GPU‑limited, upscale: render lower, output native. Example 1440p→4K: `-w 2560 -h 1440 -W 3840 -H 2160 --fsr-sharpness 3`.

- HDR (AMD + Wayland): use the `gamescope-hdr` wrapper or add `--hdr-enabled` to Gamescope.
  - Require: monitor HDR on, recent kernel/Mesa, Gamescope with HDR enabled.
  - Some titles need in‑game HDR toggled after starting in HDR mode.

- Latency and stability:
  - Prefer per‑game CPU set: `GAME_PIN_CPUSET=14,15,30,31 game-run %command%`. If a game spawns many threads, widen (e.g. `14-15,28-31`).
  - Keep VRR on: `--adaptive-sync`. If tearing or sync issues, test without it and/or cap FPS slightly below max (e.g. 237 on 240 Hz) via in‑game limiter or MangoHud.
  - Optional: test Gamescope `--rt` (realtime scheduling). If audio/input jitter occurs, remove it.

- Proton settings (per‑game, in Steam > Properties > Compatibility):
  - Proton‑GE often improves performance/compat (already installed). Switch back to Valve Proton if regressions.

- MangoHud overlay:
  - Toggle with `MANGOHUD=1`. FPS limit example: `MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game-run %command%`.

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
  - Reuse per‑game launch: `game-run %command%` (Steam), `game-run <path>` (outside Steam).

### Opinionated Presets (my own picks)

These presets are subjective and experimental — I came up with them myself. Use them as starting points and tweak for your rig/game.

- Competitive FPS (lowest latency, 240 Hz VRR):
  - Steam Launch Options:
    - `GAME_PIN_CPUSET=14,15,30,31 MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game-run gamescope -f --adaptive-sync -r 240 -- %command%`
  - Notes: cap below max refresh (237/240) for steadier frametimes; try adding `--rt` to Gamescope if stability is OK; turn off in‑game V‑Sync.

- Cinematic Single‑Player (quality first, steady 120 FPS feel):
  - If native 4K sustainable: `game-run gamescope -f --adaptive-sync -r 120 -- %command%`
  - If GPU‑bound: 1800p→4K upscale: `game-run gamescope -f --adaptive-sync -r 120 -w 3200 -h 1800 -W 3840 -H 2160 --fsr-sharpness 3 -- %command%`
  - Notes: on 240 Hz panel 120 FPS also feels smooth with VRR and frees headroom for HDR/RT.

- Heavy DX12/Open‑World (e.g., RT heavy):
  - Start conservative: `TARGET_FPS=110 game-run gamescope -f --adaptive-sync -- %command%`
  - Optional RADV toggles (may change with Mesa versions): `RADV_PERFTEST=gpl shadercache` — only if you know what you're doing.

- Strategy/Sim With Many Worker Threads:
  - Widen CPU set for the game: `GAME_PIN_CPUSET=12-15,28-31 game-run %command%`
  - If stutters from background tasks — keep Gamescope and MangoHud, but drop `--rt`.

- Emulators / Older GL Titles:
  - `MESA_GLTHREAD=true game-run %command%`
  - For strict frame pacing, prefer integer scale in Gamescope or cap FPS to native rate divisors.

- HDR Titles:
  - `game-run gamescope --hdr-enabled -f --adaptive-sync -- %command%`
  - In‑game HDR must be toggled; verify monitor HDR OSD and Gamescope logs.

Tuning tips:
- If input lag grows, remove `--rt` and lower FPS cap slightly.
- If GPU sits at 99% with spikes, reduce render resolution (`-w/-h`) or apply in‑game upscalers (FSR/DLSS/XeSS) while keeping Gamescope output at native.
- If CPU spikes, reduce background activity, or allow more CPUs in `GAME_PIN_CPUSET`.

## Lightweight Monitoring (Gaming PC)

- Netdata (local, very light):
  - Enable per-host: set `monitoring.netdata.enable = true;` (see hosts/telfir/services.nix).
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
