# Repository Overview

This repository contains the system-wide NixOS configuration together with the legacy Home Manager
flake (under `home/`). The NixOS modules are the single source of truth: all packages and services
are wired from `modules/`, while the Home Manager tree stays available for standalone/remote setups
and development. The documentation below replaces the duplicated READMEs from both projects so that
every workflow points to the same manual.

## Working Tree Layout

- `modules/`, `packages/`, `docs/`, `hosts/`, … — system configuration and documentation.
- `home/` — legacy Home Manager modules (not a standalone flake); reused by the root flake.
- `templates/` — developer scaffolding (Rust crane, Python CLI, shell app).
- `docs/manual/manual.*.md` — canonical guides (this file).

## Quick Start (System)

- Rebuild: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`
- Flake options: `nix run .#gen-options`
- Formatting/lint: `just fmt`, `just lint`, `just check`
- Hooks (optional): `just hooks-enable`

## Quick Start (Home Manager)

### Prerequisites

1. Install Nix with flakes enabled (`experimental-features = nix-command flakes`).
2. Bootstrap Home Manager via flakes:
   `nix run home-manager/master -- init --switch`
3. Optional helper: `nix profile install nixpkgs#just`

### Clone & Switch Profiles

- Clone the repo root (there is no `home/flake.nix`); run Home Manager via the root flake:
  `home-manager switch --flake .#neg` (or `just hm-neg`).
- Build without switching: `just hm-build`.
- Unified repo reminder: prefer `sudo nixos-rebuild switch --flake /etc/nixos#<host>`; the `hm-*`
  targets remain for standalone/dev workflows (same root flake).

### Profiles & Feature Flags

- Primary toggle: `features.profile = "full" | "lite"` (lite disables GUI/media/dev stacks).
- Feature definitions live in `modules/features.nix`; documentation: `OPTIONS.md`.
- Key flags:
  - GUI (`features.gui.*`), Web (`features.web.*`), Secrets (`features.secrets.enable`)
  - Dev stacks (`features.dev.*`, `features.dev.openxr.*`, `features.dev.unreal.*`)
  - Media/Torrent (`features.media.*`, `features.torrent.enable`)
  - Finance (`features.finance.tws.enable`), Fun extras (`features.fun.enable`)
  - Package exclusions by pname via `features.excludePkgs`

Inspect flattened flags: `just show-features` (set `ONLY_TRUE=1` to hide `false` values).

### Everyday Commands

- Formatting: `just fmt`
- Checks: `just check`
- Lint only: `just lint`
- Switch HM profiles: `just hm-neg` / `just hm-lite`
- Status/logs helper: `just hm-status` (`systemctl --user --failed` + journal tail)

### Secrets (sops-nix / vaultix)

- Secrets live under `secrets/` and are wired via sops-nix; vaultix migration docs now live in
  `docs/vaultix-migration.{md,ru.md}`.
- Age keys should reside in `~/.config/sops/age/keys.txt`.
- Cachix token is tracked via `secrets/cachix.env` (sops file).

### Systemd (User) Services

- Prefer `config.lib.neg.systemdUser.mkUnitFromPresets` to attach the correct targets:
  `graphical`, `netOnline`, `defaultWanted`, `timers`, `dbusSocket`, `socketsTarget`.
- Manage services via `systemctl --user start|stop|status <unit>`, logs via
  `journalctl --user -u <unit>`.

### Hyprland & GUI Notes

- Hyprland autoreload stays off; reload manually via the keybinding.
- Hypr config is split under `modules/user/gui/hypr/conf/*` and linked via Home Manager.
- `~/.local/bin/rofi` wrapper enforces consistent flags, auto-select, and theme lookup in XDG
  paths; disable auto-select per call with `-no-auto-select`.
- Quickshell keyboard layout indicator listens to Hyprland `keyboard-layout` events, prefers the
  `main: true` device, and uses `hyprctl switchxkblayout current next` on click.
- Floorp customizations keep the nav bar on top and strip telemetry/Activity Stream noise by
  default; toggle advanced tweaks in `modules/user/web/floorp.nix` if needed.
- Swayimg wrappers (`swayimg-first`) land in `~/.local/bin/swayimg` and are tuned via Hyprland
  window rules.

### Miscellaneous Developer Notes

- Commit format: `[scope] message` (enforced by `.githooks/commit-msg` if enabled).
- Hyprland plugins and portals are pinned through the system flake inputs; see the sections below
  for update policies.

## Agent Guide & Conventions

Use the same expectations regardless of whether you work under `modules/` or `home/`; helpers live
side-by-side so the patterns apply to both configurations.

### Key Locations

- Core helpers: `modules/lib/neg.nix`
- XDG helpers: `modules/lib/xdg-helpers.nix`
- Feature definitions/options: `modules/features.nix`

### Package Availability Checks

- Before adding any `pkgs.*`/`nodePackages_*`, confirm the attribute exists using
  `nix search` (or any flake evaluation) against this repo. Only wire packages that exist in the
  currently pinned channel.

### QML / Quickshell Touches

- Stick to upstream Qt 6 best practices: small declarative components, property bindings over the
  imperative approach, no binding loops or global JS helpers, explicit signal handlers.
- Assume Qt 6+ APIs; review the latest Hyprland/Quickshell release notes before suggesting changes.
- Automated QML linters are currently unavailable, so rely on these conventions.

### XDG Helpers (Preferred)

- Use `xdg.mkXdgText`, `xdg.mkXdgSource`, `xdg.mkXdgDataText`, `xdg.mkXdgDataSource`,
  `xdg.mkXdgCacheText`, and `xdg.mkXdgCacheSource` instead of ad‑hoc `home.file` or shell commands.
- JSON/TOML shortcuts: `xdg.mkXdgConfigJson`, `xdg.mkXdgDataJson`, `xdg.mkXdgConfigToml`,
  `xdg.mkXdgDataToml`.

### Conditional Sugar

- `config.lib.neg.mkWhen` / `mkUnless` wrap `lib.mkIf`. Prefer them for readability when enabling
  chunks under feature flags.

### Activation Helpers

- `mkEnsureRealDir` / `mkEnsureRealDirsMany` for directories before `linkGeneration`.
- `mkEnsureAbsent` / `mkEnsureAbsentMany` to delete conflicting paths pre‑activation.
- `mkEnsureDirsAfterWrite` and `mkEnsureMaildirs` for post‑writeBoundary directory creation.
- Use per-file `force = true` instead of re‑adding global XDG cleanup.
- Local scripts: `config.lib.neg.mkLocalBin name text` removes conflicts and marks the file
  executable before linking.

### Systemd (User) Pattern

- Always combine `lib.mkMerge` with `config.lib.neg.systemdUser.mkUnitFromPresets` for consistent
  `After=/WantedBy=` wiring; avoid the legacy `mkSimple*` helpers (they have recursion edge cases).
- Examples:
  - Service: preset `["defaultWanted"]`
  - Timer: preset `["timers"]`

### Rofi Wrapper Notes

- `~/.local/bin/rofi` injects safe defaults: `-no-config`, `-auto-select`, Ctrl+C cancel bindings,
  theme resolution relative to XDG paths, Hyprland/Quickshell offset detection.
- Keep per-call options minimal; if you need custom keybindings pass them explicitly (the wrapper
  will respect overrides).
- Pinentry uses `pinentry-rofi` with the `askpass` theme by default; override via
  `PINENTRY_ROFI_ARGS` if you need custom flags.

### Editor Shim

- Use `v` (Neovim shim at `~/.local/bin/v`) in bindings/scripts that expect a short editor name.

### Soft Migrations / Warnings

- Emit guidance with `warnings = lib.optional cond "message";` instead of `builtins.trace`.
- Keep warning conditions cheap and avoid referencing `config.lib.neg` while evaluating options.

### Commit Messages

- Stick to `[scope] summary`.
  `[quickshell/gui] improve keyboard indicator`.
- Scopes can be combined via `/` (e.g. `[cli/gui] …`) when touching multiple areas.

## Coding Style

- Formatting: run `nix fmt`/`just fmt` (treefmt) before committing. It runs `alejandra -q` for Nix
  and `mdformat --wrap 100` for Markdown. Enable git hooks via `just hooks-enable` to auto-run
  formatters (`SKIP_NIX_FMT=1` to skip).
- Indent with 2 spaces; let alejandra control wrapping/spacing. Avoid manual column alignment.
- Lists with complex elements expand one per line; attribute sets become multi-line once they hold
  more than one entry.
- Keep prose/strings around ~100 columns; move long comments above the expression they describe.
- Avoid `with pkgs;` around lists—refer to `pkgs.foo` explicitly. Using `with` inside local
  attrsets or helper scopes is fine.
- Always declare feature options centrally (see `modules/features.nix`) and gate module
  fragments via the relevant `features.*` flags.
- Structure modules with `lib.mkMerge [ … ]` and the helper sugar above. Factor package groups into
  local `groups = { … };` sets and flatten with `config.lib.neg.mkEnabledList`.
- Systemd user units/paths/sockets should reuse `config.lib.neg.systemdUser.mkUnitFromPresets`.
- For xdg-managed files prefer the helpers from `modules/lib/xdg-helpers.nix` (text/source/data/
  cache, JSON/TOML). They ensure parent directories exist as real dirs and remove conflicting paths
  before linking.
- Use `config.lib.neg.mkLocalBin` for scripts under `~/.local/bin`.
- Keep warnings actionable via `warnings = lib.optional cond "…";` and ensure the condition is
  cheap (avoid referencing `config.lib.neg` while declaring the warning).
- Commit messages must follow `[scope] subject` unless performing `Merge`, `Revert`, `fixup!`,
  `squash!`, or `WIP`.

## Third-Party Components

Keep this manifest updated whenever vendored sources change so that licensing remains clear.

| Component | Source | Revision | License | Notes |
|-----------|--------|----------|---------|-------|
| awrit | [github.com/chase/awrit](https://github.com/chase/awrit) | tag `awrit-native-rs-2.0.3` | BSD-3-Clause | Terminal Chromium renderer (`pkgs.neg.awrit`). |
| cantata | [github.com/nullobsi/cantata](https://github.com/nullobsi/cantata) | `a19efdf9649c50320f8592f07d82734c352ace9c` | GPL-3.0-only | MPD Qt client with extra patches (`pkgs.neg.cantata`). |
| kitty-kitten-search | [github.com/trygveaa/kitty-kitten-search](https://github.com/trygveaa/kitty-kitten-search) | `992c1f3d220dc3e1ae18a24b15fcaf47f4e61ff8` | *No license declared upstream* | Provides `search.py` / `scroll_mark.py` kittens for Kitty. Verify licensing before distributing binaries. |

## Open Tasks

- Teach `nix flake check` (or a dedicated `hm-extras` job) to build `pkgs.neg.cantata` so the Qt
  patches stay tested automatically.
- Document the Firefox multi-profile stack (profiles, desktop entries, addon requirements) once the
  layout stabilises.
- Populate secrets/env vars for the new MCP stack so `seh` can finish without placeholders. Needed
  providers: Gmail (`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN`,
  `OPENAI_API_KEY`), Google Calendar (`GCAL_CLIENT_ID`, `GCAL_CLIENT_SECRET`, `GCAL_REFRESH_TOKEN`,
  optional `GCAL_ACCESS_TOKEN`, `GCAL_CALENDAR_ID`), IMAP (`IMAP_HOST`, `IMAP_PORT`,
  `IMAP_USERNAME`, `IMAP_PASSWORD`, `IMAP_USE_SSL`), SMTP (`SMTP_HOST`, `SMTP_PORT`,
  `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_ADDRESS`, `SMTP_USE_TLS`, `SMTP_USE_SSL`, optional
  `SMTP_BEARER_TOKEN`), GitHub (`GITHUB_TOKEN`, optional `GITHUB_HOST`, `GITHUB_TOOLSETS`,
  `GITHUB_DYNAMIC_TOOLSETS`, `GITHUB_READ_ONLY`, `GITHUB_LOCKDOWN_MODE`), GitLab (`GITLAB_TOKEN`,
  `GITLAB_API_URL`, optional `GITLAB_PROJECT_ID`, `GITLAB_ALLOWED_PROJECT_IDS`,
  `GITLAB_READ_ONLY_MODE`, `USE_GITLAB_WIKI`, `USE_MILESTONE`, `USE_PIPELINE`), Discord
  (`DISCORD_BOT_TOKEN`, optional `DISCORD_CHANNEL_IDS`).

## Evaluation Noise Policy

- No evaluation-time warnings or traces. Keep builds and switches quiet.
- Do not use `warnings = [ ... ]`, `builtins.trace`, or `lib.warn` in modules.
- If a package/feature is unavailable, silently skip or guard with a flag. Document behavior in module docs/README instead of emitting warnings.
- Use assertions only for truly fatal misconfigurations that would break the system, and phrase them concisely.

## Custom Packages Overlay

- All local derivations (`pkgs.neg.*`, CLI wrappers, MCP servers, etc.) now live under the top-level `packages/` directory instead of `home/packages/`.
- The system modules add this overlay via `modules/nix/home-overlay.nix`; the Home Manager flake reuses it through `../packages/overlay.nix` so both sides see the same package set.
- When working inside `home/`, remember paths now need one more `../` to reach the shared `packages/` tree.
- Flake outputs for the custom servers are exposed at the repository root (e.g. `nix build .#mcp-server-filesystem`), so you no longer need to enter `home/` to package or publish them.

## Hyprland: Single Source of Truth and Updates

- Source of truth: `inputs.hyprland` (compositor) tracks Hyprland v0.52.1 while `inputs.hy3` stays pinned to `hl0.51.0` (last stable plugin tag); `flake.lock` still captures the exact commits.
- The NixOS overlay routes `pkgs.hyprland`, `pkgs.xdg-desktop-portal-hyprland`, and `pkgs.hyprlandPlugins.hy3` to those inputs, so Home‑Manager modules can just use `pkgs.*`.
- Supporting inputs stay in lockstep via `follows` (`hyprland-protocols`, `xdg-desktop-portal-hyprland`, etc.); no manual portal wiring beyond `programs.hyprland.portalPackage = pkgs.xdg-desktop-portal-hyprland`.
- Do not add `xdg-desktop-portal-hyprland` to `xdg.portal.extraPortals` — the package already provides the portal service when set as `portalPackage`.

How to update Hyprland (and hy3):

1) Refresh the pins: `nix flake update hyprland hy3` (other Hyprland inputs follow automatically).
2) Rebuild the system: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.

Auto‑update (optional): if `system.autoUpgrade` with flakes is enabled, add `--update-input hyprland --update-input hy3` when you deliberately move to the next Hyprland release. We usually bump manually to keep ABI changes under control.

## Roles & Profiles

- Roles: enable bundles via `modules/roles/{workstation,homelab,media}.nix`.
  - `roles.workstation.enable = true;` → desktop defaults (performance profile, SSH, Avahi).
  - `roles.homelab.enable = true;` → self‑hosting defaults (security profile, DNS, SSH, MPD).
  - `roles.media.enable = true;` → media servers (Jellyfin, MPD, Avahi, SSH).
- Profiles: feature flags under `modules/system/profiles/`:
  - `profiles.performance.enable` and `profiles.security.enable` are toggled by roles; override per host if needed.
- Service profiles: toggle per‑service via `profiles.services.<name>.enable` (alias to `servicesProfiles.<name>.enable`).
  - Roles set `mkDefault true`; hosts can disable with plain `false` (no mkForce needed).
- Host‑specific config: keep concrete settings under `hosts/<host>/*.nix`.
  - Examples: NIC names, local DNS rewrites.

Example (host):

```nix
{ lib, ... }: {
  roles = {
    workstation.enable = true;
    homelab.enable = true;
  };

  # Disable heavy services for VMs or minimal builds
  profiles.services = {
    adguardhome.enable = false;
  };
}
```

Example (media role):

```nix
{ lib, ... }: {
  roles.media.enable = true;

  # This role enables Jellyfin, MPD, Avahi, SSH by default.
  # Per-host overrides (e.g., disable Jellyfin on this machine):
  profiles.services.jellyfin.enable = false;

  # Media server host-specific tweaks can live here as well (paths, ports, etc.).
}
```

Service override examples

```nix
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
- patches-amd: `boot.kernelPatches` with `extraStructuredConfig` for AMD in `modules/system/kernel/patches-amd.nix`.
- Feature toggles: tune via `profiles.performance.*` and `profiles.security.*`; params derive from these.

### PREEMPT_RT

- Toggle: `profiles.performance.preemptRt.enable = true;`
- Mode: `profiles.performance.preemptRt.mode = "auto" | "in-tree" | "rt";`
  - `auto`: use in-tree `CONFIG_PREEMPT_RT` on kernels >= 6.12, otherwise switch to `linuxPackages_rt`.
  - `in-tree`: force enabling `CONFIG_PREEMPT_RT` on the current kernel package (no package switch).
  - `rt`: switch kernel package to `pkgs.linuxPackages_rt` explicitly.

Note: extra out-of-tree modules (e.g., `amneziawg`) are pulled from the selected `boot.kernelPackages` when available.

### Debug/Profiling (optional)

- Memory allocation profiling (6.10+): `profiles.debug.memAllocProfiling.{enable,compileSupport,enabledByDefault,debugChecks}`.
- perf data-type profiling (6.8+): `profiles.debug.perfDataType.{enable,installTools,enableKernelBtf}`.
  - These options may rebuild the kernel when enabling related `CONFIG_*` symbols.

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
    # autoFancontrol.allowStop = false;      # allow fans to fully stop below minTemp
    # autoFancontrol.gpuPwmChannels = [ ];   # PWM channels (e.g., [2 3]) to follow GPU temp
  };
}
```

- Notes:
- The generator uses CPU temperature (`k10temp`) to drive all motherboard PWM channels (nct6775).
- If `gpuFancontrol.enable = true`, GPU fan (amdgpu pwm1) is driven by GPU temp (prefer junction sensor when available).
- If `/etc/fancontrol` already exists, it is backed up once to `/etc/fancontrol.backup` and replaced with a symlink to `/etc/fancontrol.auto`.
- GPU fans remain managed by the GPU driver; only motherboard PWM headers are targeted.
  - Exception: when `gpuFancontrol.enable = true`, we switch `pwm1_enable` to manual and fancontrol takes over.

### Fan stop capability test

- Utility: `fan-stop-capability-test` checks which motherboard PWM channels can fully stop at 0%.
- Safe by default: skips CPU/PUMP/AIO headers; restores original settings after probing.
- Usage examples:
  - List channels only: `sudo fan-stop-capability-test --list`
  - Test chassis fans: `sudo fan-stop-capability-test`
  - Include CPU/PUMP (at your own risk): `sudo fan-stop-capability-test --include-cpu`
- Options: `--device <hwmonN|nct6798>`, `--wait <sec>` (default 6), `--threshold <rpm>` (default 50).
- Note: stop `fancontrol` during the test for accurate results: `sudo systemctl stop fancontrol`.

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
## DNS Resolver Monitoring

- Unbound + Prometheus + Grafana dashboard for DNS quality (latency, DNSSEC validation, cache hits): see `docs/unbound-metrics.md`.


---

# AGENTS: Tips and pitfalls found while wiring monitoring and post-boot

Post‑Boot Systemd Target
- Don’t add `After=graphical.target` to the `post-boot.target` itself; `graphical.target` already wants `post-boot.target`. Adding `After=graphical.target` on the target creates an ordering cycle.
- When deferring services to post‑boot, avoid blanket `After=graphical.target` in the helper that attaches units to `post-boot.target`. Let the target be wanted by `graphical.target`, and only add specific `After=` edges per service if strictly required (never the target itself).

Wi‑Fi via iwd profile
- The base network module installs iwd tooling but sets `networking.wireless.iwd.enable = false` so wired hosts don’t start it needlessly.
- To give a host Wi‑Fi controls, toggle `profiles.network.wifi.enable = true;` (e.g. inside `hosts/<name>/networking.nix`) instead of hand-written `lib.mkForce` overrides.

Prometheus PHP‑FPM Exporter
- Socket access: the exporter scrapes a PHP‑FPM unix socket (for example, `unix:///run/phpfpm/app.sock;/status`). Ensure the PHP‑FPM pool socket is group‑readable by a shared web group and the exporter joins it:
  - Configure the PHP‑FPM pool: set `"listen.group" = "nginx";` and `"listen.mode" = "0660"`.
  - Add both `caddy` and `prometheus` users to the `nginx` group via `users.users.<name>.extraGroups = [ "nginx" ];`.
- Unit sandboxing: the upstream exporter unit can prohibit UNIX sockets with `RestrictAddressFamilies`.
  - Allow AF_UNIX: set `RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];`.
  - Ensure the unit has access to the socket group: `SupplementaryGroups = [ "nginx" ];`.
- DynamicUser vs. real user: the upstream module may use `DynamicUser=true` and `Group=php-fpm-exporter`. If you need the exporter to inherit static group membership, override with higher priority:
  - `DynamicUser = lib.mkForce false; User = lib.mkForce "prometheus"; Group = lib.mkForce "prometheus";`.
- Emergency switch safety: if activation is blocked by the exporter while debugging, temporarily disable it to unblock a `switch`: set `services.prometheus.exporters."php-fpm".enable = false;` and re‑enable after fixing permissions/ordering.
- Common mistakes to avoid:
  - Misplacing user group options: within the `users = { ... }` attrset, set `users.caddy.extraGroups = [ "nginx" ];` and `users.prometheus.extraGroups = [ "nginx" ];` (this maps to `users.users.<name>.extraGroups`). Don’t write `users.users.caddy` again inside `users = { ... }` — that becomes `users.users.users.caddy` and fails evaluation.
  - Enabling multiple proxies: don’t enable multiple reverse proxies for the same backend (such as both nginx and Caddy for the same socket/port); pick a single proxy per backend.

Nextcloud on telfir (clean install)
- Host `telfir` uses the stock `services.nextcloud` module without custom profiles; the web frontend is Caddy (`services.caddy`) in front of the Nextcloud PHP‑FPM pool.
- Nextcloud is served at `https://telfir` with initial credentials: user `admin`, password `Admin123!ChangeMe` (see `hosts/telfir/services.nix:services.nextcloud.config`).
- The data directory is isolated from any previous installs (`/zero/sync/nextcloud`), and the MariaDB/MySQL database is created locally under the default user `nextcloud` (`database.createLocally = true;`).
- To reset the admin password, use `sudo -u nextcloud /run/current-system/sw/bin/nextcloud-occ user:resetpassword admin`. The current password (`Admin123!ChangeMe` by default) is tracked via the SOPS secret `secrets/nextcloud-admin-password.sops.yaml`.
  - The password is materialized into `/var/lib/nextcloud/adminpass` (owned by `nextcloud`, mode `0400`) via the `nextcloud-adminpass-from-sops` unit.
  - The automatic `nextcloud-setup` and `nextcloud-update-db` units are disabled; upgrades are performed manually with `sudo -u nextcloud nextcloud-occ upgrade` after bumping the Nextcloud package version.
