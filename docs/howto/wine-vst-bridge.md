# Windows VSTs on Linux via Wine — comparison of solutions (odin)

> Research 2026-08-20, gathered by subagents from primary sources (GitHub, nixpkgs 26.05, Carla
> sources). Unresolved spots are marked [unverified] — they need a live check on odin. Context: NixOS
> 26.05, wineWow64Packages.stable (wine 11), PipeWire (pw-jack, no jackd), Carla from nixpkgs
> (JACK-only, wine bridge NOT built).

## Comparison table

| Solution | What it does | Formats | 32/64 | wine | Headless/CLI | Carla/carlactl integration | Nixpkgs | Status | License | CLI rating\* |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Carla wine bridge** (`make win32/win64/wine32/wine64` from Carla sources) | Native Carla spawns one `wine carla-bridge-win64.exe` per plugin; IPC via shared memory | VST2 + VST3 (no CLAP) | 32+64 (win32/win64 bridges) | runtime wine + auto-detected prefix from the DLL path (directory with `dosdevices`); wineasio NOT needed (JACK provides `jackbridge-wine*.dll`) | `carla -n <file.carxp>` (a project is mandatory), `--osc-gui=<port>`; carlactl-compatible (C API: `carla_add_plugin(BINARY_WIN64, PLUGIN_VST2, dllPath,…)`) | Ideal: same C API, binary in `$out/lib/carla`, PE file type detected by libmagic, scan via `carla-discovery-win64.exe` under wine | **No** (issue #324094; needs an overlay: mingw-w64 + winegcc, 4 make targets) [unverified build] | Active (v2.5.10 2025-07, commits 2026) | GPL-2.0-or-later | 3 |
| **yabridge** | Linux .so chainloaders in `~/.vst{,3}/yabridge`, spawn the wine process `yabridge-host.exe`; UDS + shared memory | VST2 + VST3 + **CLAP** | 64-bit; 32-bit Windows plugins do NOT work (bitbridge is incompatible with WoW64; nixpkgs builds with `-Dbitbridge=false`) | nixpkgs pins **wine 9.21** (`wineWow64Packages.yabridge`, WINELOADER hardcoded) — bypasses the 9.22/10.x incompatibility [unverified: will wineapps prefixes on wine 11 open with this wine 9.21] | No standalone (a host is needed); with Carla: VST2/VST3 OK (README tested-hosts); via carlactl: `carlactl list`/`run vst3:Name` (symlinks are picked up from the `~/.vst3`, `~/.vst` roots) [unverified end-to-end] | Good: symlinks are visible to carlactl automatically; `yabridgectl add/sync/status` | **Yes: 5.1.1** — and already installed on odin (`modules/hardware/audio/dsp.nix`) | Active (5.1.1 2024-11, commits 2026-08) | GPL-3.0 | 2–3 |
| **linvst / linvst3** | Per-plugin .so (linvst.so + lin-vst-server); the DAW scans the .so, the plugin lives in wine | VST2; VST3 — separate **LinVst3** (beta, 64-bit only, not all features) | 64; 32-bit needs win32-wine (Arch wow64 cannot) | any modern 64-bit wine | A GUI host is needed; CLI linking scripts exist | Loads in Carla as a normal .so → carlactl can see it | **No** | Active (2025-12; release 4.9 2023) | GPL-3.0 | 1 |
| **airwave** | Wine VST bridge → .so for Linux hosts; shared memory + XEMBED | VST 2.4 only | 32+64 (multilib wine) | wine ≥ 1.7.19 | A host is needed | As a normal .so | **Yes: 1.3.3** | Dead (2020-07) | MIT | 1 |
| **vst-bridge** | The CLI `vst-bridge-maker` converts .dll → .so; the .so spawns a wine host | VST2 only | 32+64 | wine + WINEPREFIX | CLI-maker exists, a host is needed | As a .so | **No** | Dead (2019) | MIT | 1 |
| **wineasio** (audio driver, not a bridge) | ASIO→JACK DLL; per-prefix registration (`wineasio-register`) | — | 32+64 | any; wine 11 may require renaming `wineasio64.so` | CLI registration exists; for standalone .exe | JACK via pw-jack | **Yes: 1.3.0** | Active (2025-07) | LGPL-2.1 | 2 |
| **pwasio / pipeasio** (audio drivers) | ASIO→**PipeWire** (without the JACK layer) | — | 64 | PipeWire ≥ 1.6 / 1.4.2 | CLI registration; for standalone .exe | native PipeWire | **No** (needs packaging) | Active (2026-08) | GPL-3.0 | 2 |
| **Standalone .exe + ASIO driver** | A Windows VST with its own standalone binary runs under wine and opens JACK/PW ports | depends on the VST | same as the VST | wineapps prefix + wineasio/pwasio/pipeasio | Fully scriptable: `wine app.exe` + `jack_connect`/`pw-link`; MIDI via ALSA-seq/a2jmidid [unverified] | Independent of Carla | — | — | — | 2–3 |
| **VSTHost / SAVIHost** (Windows freeware) | Windows host under wine: `savihost.exe` next to the .dll = standalone app | VST2+VST3 | 32+64 | wine + ASIO driver | config files, CLI invocation | via JACK | — | freeware (closed-source) | — | 2 |
| **MrsWatson** | Native Linux CLI VST host: `mrswatson --input in.mid --output out.wav --plugin <x.so>` | loads .so (incl. linvst/airwave/vst-bridge wrappers) | 64 | not needed (wine only for wrappers) | **Pure CLI end-to-end** | — | fork in nixpkgs? (not checked) | original archived, fork alive | BSD | 3 |
| **Docker approach** (bitwigbox etc.) | wine+plugins in a container | depends | 64 | inside the container | via host JACK | — | — | active | — | 1 |

\*CLI rating: 0 = none, 1 = CLI conversion exists but a GUI host is needed, 2 = scriptable CLI flow, 3 =
pure CLI end-to-end.

## Recommendation for odin (working setup 2026-09-01)

**Carla and carlactl were removed** (commit “Remove Carla stack”): **yabridge** (nixpkgs, installed on
odin, 5.1.1) makes Windows VSTs ordinary Linux VST3/VST2 in `~/.vst3/yabridge` / `~/.vst/yabridge`, and
**Renoise** (already in systemPackages) loads them as normal VSTs. VSTPlugin in SuperCollider does NOT
suit yabridge bridges (its search blacklists them: yabridge-host requires an external host process,
VSTPlugin dlopens the .so directly) — so the host is Renoise.

Installing Windows VSTs (all into the `vstplugins` prefix):

1. VST prefix under wine 9.21 (yabridge host): `wineboot -u` from
   `/nix/store/...-wine-wow64-yabridge-9.21/bin/wineboot`.
1. Windows VSTs install into the prefix (e.g. ReaPlugs 2.36 x64 — officially wine-tested,
   `/gamez/main/wineapps/reaplugs236_x64-install.exe /S`).
1. `mkdir -p ~/.local/share/yabridge && ln -sf /run/current-system/sw/lib/libyabridge* ~/.local/share/yabridge/`
   → `yabridgectl add "<prefix>/drive_c/Program Files/VSTPlugins/<App>" && yabridgectl sync`.

Run: `synth LegendHZ` (or any other yabridge plugin) opens Renoise — the plugin appears in the VST3
list on the track FX chain. Bridge status check: `yabridgectl status`. Verified: ReaEQ (ReaPlugs) →
yabridge 5.1.1 → Renoise (ordinary VST2).

## Key sources

- Carla wine bridge: https://github.com/falkTX/Carla (INSTALL.md:101–118, CarlaPluginBridge.cpp,
  CarlaBackend.h:1493–1518), nixpkgs issue #324094, https://kx.studio/Applications:Carla. Caution: an
  open regression `carla --no-gui` #1828 (2.5.7+).
- yabridge: https://github.com/robbert-vdh/yabridge (README, docs/architecture.md,
  tools/yabridgectl/README.md), nixpkgs: pkgs/by-name/ya/yabridge + yabridgectl (wine 9.21,
  -Dbitbridge=false), issues #300755, #399465.
- linvst: https://github.com/osxmidi/LinVst ; LinVst3: https://github.com/osxmidi/LinVst3
- airwave: https://github.com/psycha0s/airwave ; vst-bridge: https://github.com/abique/vst-bridge
- wineasio: https://github.com/wineasio/wineasio ; pwasio: https://github.com/golfiros/pwasio ;
  pipeasio: https://github.com/M0n7y5/pipeasio
- MrsWatson (fork): https://github.com/adamnemecek/MrsWatson ; VSTHost/SAVIHost:
  https://syntheway.com/Hermann_Seib_VSTHost_v1.53_SAVIHost_v1.41.htm
- Wine workflows for VST: https://wiki.nixos.org/wiki/Electric_guitar_interface_setup

\*Open questions: (1) Carla bridge JACK under pw-jack (LD_LIBRARY_PATH gets cleaned,
jackbridge-wine.dll resolves libjack) [unverified];

- (2) 32-bit bridge under WoW64 wine 11 [unverified]; (3) yabridge + wine 11 prefix [unverified];
- (4) building Carla bridges in an overlay [unverified].

## Installing VST packages (verified 2026-08-20, all into the `vstplugins` prefix)

- **ReaPlugs 2.36 x64** (Cockos): `wine reaplugs236_x64-install.exe /S` →
  `drive_c/Program Files/VSTPlugins/ReaPlugs/` (10 VST2 dlls).
- **The Legend HZ 2.1.0** (Synapse): `wine Legend_HZ_2_1_Setup.exe /S` →
  `Program Files/Steinberg/VSTPlugins/LegendHZ.dll` (VST2) +
  `Program Files/Common Files/VST3/Synapse Audio/LegendHZ.vst3` (VST3) + AAX.
- **kiloHearts Ultimate v2.4.6** (4.3 GB): InnoSetup — `/S` does NOT work (exit 5); needs
  `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` → `Program Files/Common Files/VST3/kiloHearts/` (48
  plugins: Snap Heap, Disperser, Multipass, kHs modules; Phase Plant removed 2026-08-25 (would not
  start under yabridge — a “failed to start wine host”-class problem, see below).
- After installation: `yabridgectl add <directory with dll/vst3>` + `yabridgectl sync`; check
  `yabridgectl status`.

### Legend HZ: “run as administrator”

- The plugin loads headless fine (yabridge init OK); the message comes from the Synapse licensing layer
  when the UI opens.
- Causes: (1) silent `/S` does not create `Program Files/Synapse Audio/The Legend HZ/` (create it
  manually); (2) without registration/keygen the plugin stays in demo mode.
- Valhalla releases from torrents (`R2R/`, `R2RINNO.dll` in the installer temp) are cracked installers,
  we do not run them; keygens/patches neither.

## “The Wine host process has exited unexpectedly” in GUI hosts (fixed)

- **Symptom**: in the Carla GUI (and any desktop host) yabridge plugins crash with “The Wine host
  process has exited unexpectedly”; in the GUI patchbay the plugin has no MIDI port.
- **Cause**: `modules/user/nix-maid/cli/envs.nix` globally set
  `WINEPREFIX=~/.local/share/wineprefixes/default`. With that variable set, yabridge does NOT detect
  the prefix from the plugin path (yabridge README: WINEPREFIX overrides the Wine prefix for all
  yabridge plugins) — the wine host started in the empty `default` prefix and crashed.
- **Fix**: the global `WINEPREFIX` was removed from `envs.nix` (commit 8fa747a0); yabridge finds the
  prefix itself from the location of `.dll/.vst3` (`vstplugins`). Check: `bash -lc 'echo $WINEPREFIX'` is empty.
  After rebuilding the desktop session a re-login is needed (old processes keep the old env).
- **Red/green**: `WINEPREFIX=…/default yabridgectl sync` → the host starts in an empty prefix;
  `WINEPREFIX=…/vstplugins` (default path, no global WINEPREFIX) →
  `Finished initializing '…LegendHZ.vst3'`, the host stays alive.

## Playable chain: Renoise + yabridge + physical keyboard

- Host — Renoise: `synth LegendHZ` launches it; on the track FX → VST3 → LegendHZ (the yabridge bridge
  looks like an ordinary VST3).
- MIDI: physical keyboard (RME MIDI IN) → Renoise: enable the MIDI input in settings (Renoise sees
  ALSA clients; `Midi-Bridge:External MIDI:HDSPe…` is the RME port). SuperCollider → Renoise:
  `~/.local/bin/midi-bridge` (SC MIDI out0 → Renoise midi in).
- Audio: Renoise outputs via JACK/PipeWire; `pw-link` routes `renoise:out_1/2` →
  `game-stereo:playback_FL/FR` (game-stereo → RME playback_AUX2/3).
- **WARNING (fixed)**: if the PipeWire graph “drifts” to 44.1 kHz and everything crackles — in
  `files/media/pipewire/pipewire.conf.d/clock-rate.conf` only
  `default.clock.allowed-rates = [ 48000 ]` is left (commit d3758472) — the graph is locked to the
  native RME rate. Temporary analogue before a rebuild: `pw-metadata -n settings 0 clock.force-rate 48000`.

## Osmose (Expressive E) + MPE + Legend HZ (research 2026-08-21)

- **Legend HZ**: omni + native MPE (Synapse manual, section “5.1 MPE (MIDI Polyphonic Expression)”):
  listens to ALL channels; the “MPE Controller” switch — pitch bend ±48 semitones, master channel 1,
  Rise/Fall shaping for CC74/aftertouch. Source:
  https://www.synapse-audio.com/legend/TheLegendManualHZ.pdf
- **Osmose**: presets of External MIDI Mode (Config menu, turn Value Encoder 4 and press): `mpe` (by
  default: ch1 master + ch2-15 per voice), `classic keyboard` (everything on ch1 — for legacy synths),
  `poly aftertouch`, `multi-channel`. Fine tuning: Adjust menu → mode tab → “mono ch.” / “mpe” (final
  channel) / “multi ch.”. Source: Osmose Manual 1.0, §3 EXTERNAL MIDI MODE.
- **yabridge**: MIDI pass-through is transparent, channels are not normalized (there are no MIDI options
  in yabridge.toml) — MPE reaches the Windows VST unchanged.
- **yabridge per-plugin settings (yabridge.toml)**: the file sits next to the bridge —
  `~/.vst3/yabridge/yabridge.toml` (or `~/.vst/yabridge/`, `~/.clap/yabridge/`), sections glob by
  .so/.vst3 paths. Options (yabridge README 5.1, https://github.com/robbert-vdh/yabridge): `group`
  (shared process for related plugins of one vendor, e.g. FabFilter Pro-Q 3), `disable_pipes`,
  `editor_disable_host_scaling` (HiDPI VST3/CLAP editors under fractional scale), `editor_force_dnd`
  (REAPER only), `frame_rate` (default 60), `hide_daw`, `vst3_prefer_32bit`. **Legend HZ needs none of
  these**: MPE transparency is not configured in yabridge; “MPE CONTROLLER ±48 st” is a UI switch inside
  the plugin itself (section 5.1 of the Synapse manual), not a bridge option.
- **Takeaway**: for Legend HZ the Osmose mode does not need changing — MPE works directly (omni
  reception). The “dirty sound” in the first tests was NOT due to MPE or demo mode but to RME acting as
  a resampling follower (see the priority.driver fix above).
- **MPE CONTROLLER in Legend HZ** (section 5.1 of the manual): the synth is MPE-compatible “out of the
  box” (listens to all channels); the MPE CONTROLLER switch in the plugin UI additionally gives: Rise/Fall
  for CC74 (brightness) and aftertouch, pitch bend ±48 semitones, MPE master channel 1 with global bend.
  Curves: VELOCITY / TIMBRE (CC74) / ATOUCH.
- **Osmose Sensitivity menu**: 4 tabs — bending (bend range and stabilization), pressure (the first part
  of the key travel; “note on” = the position where the key really triggers the note), aftertouch (the
  second part of the travel), default sensitivity. If keys “do not respond” — lower the note-on threshold
  in the pressure tab.
- **MIDI 2.0 (UMP)**: official Expressive E answer (KB 162): Osmose does NOT support MIDI 2.0 —
  “possibly in the future, when there is enough MIDI 2.0 hardware”, MPE has priority. The manual
  (v23.1.29c) has no MIDI 2.0 at all. All expressiveness (per-note bend, CC74, aftertouch) already goes
  through MPE over MIDI 1.0 — for Legend HZ that is exactly what is needed.

## Synths: composition and switching (2026-08-21)

- **Windows (yabridge)**: Legend HZ (mono, MiniMoog-style) + 48 kiloHearts modules (FX: Snap Heap,
  Disperser, Multipass, kHs-…). Phase Plant removed (2026-08-25) — did not start through yabridge.
- **Native (Linux, no wine)**: Vital (wavetable), Dexed (FM/DX7), Surge XT (wavetable/VA,
  MPE-capable — added fc4387ea/eaf74df1). WARNING: the nixpkgs package `odyssey` is Yandex PostgreSQL
  pooler, NOT a synthesizer (verified 2026-08-21,
  `nix eval nixpkgs#odyssey.meta.description`). The real open-source ARP-Odyssey-style VA synth is
  Odin 2 (`pkgs.odin2`), but the user did not want it — the `pkgs.odyssey` line stays in the config as
  is (a deliberate decision, revert commit ceba4734).
- **Switching**: `synth <name>` — run-or-raise: Surge_XT → native standalone, Vital →
  vital-standalone, others (LegendHZ, kiloHearts, …) → Renoise (yabridge plugin on the FX chain).
- **Several synths at once**: in Renoise just add tracks/FX; SuperCollider MIDI slots (out0..N) are
  assigned via `~/.local/bin/midi-bridge` (SC → Renoise midi in) or a2jmidid. 3 slots (SC MIDIOut is
  limited by ALSA assignments: RME + Osmose×2).

## VCV Rack (license + window; research 2026-08-21/25)

- **Package**: nixpkgs `vcv-rack` = **Rack Free 2.6.6** (`/run/current-system/sw/bin/Rack`). The engine
  is free; paid modules bind to the **VCV account** (email+password), no serials.
- **Run**:
  `systemd-run --user --unit=rack --collect bash -lc 'export DISPLAY=:0 WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 XAUTHORITY=/run/user/1000/Xauthority; Rack > /tmp/rack.log 2>&1'`
  (the window is XWayland, class GLFW-Application).
- **Account login (license activation)**: Rack menu bar is compact, on the left (File/Edit/View/Engine/
  Library/Help). Clicking **Library** opens the **“Register VCV account”** dialog with Email, Password
  fields and a Log in button — enter the vcvrack.com email+password there, after which Rack downloads
  the purchased modules (Update button in the Library panel). Note: the menu of the GLFW window may only
  open on a press-and-hold click (`xdotool mousedown; sleep 0.4; xdotool mouseup`) and survives repeated
  clicks unreliably — if the menu “did not open”, repeat the hold-click.
- **Window off-screen (1921,1 etc.)**: fixed by Hyprland lua dispatchers (see the section below).
- **Window position** is stored in `~/.local/share/Rack2/settings.json` (windowX/Y are null by default;
  the window is placed by Hyprland itself).

## Hyprland 0.55: lua dispatchers for windows (research 2026-08-21)

Classic `bind =`/dispatchers are NOT registered in the lua config — only `hl.dsp.*` via
`hyprctl dispatch '<lua-expr>'`. Verified calls (for the Rack window; address from
`hyprctl clients -j`):

- `hl.dsp.window.move({ window = "address:0x…", workspace = 2 })` — to another workspace;
- `hl.dsp.window.float({ window = "address:0x…", action = "on" })` — enable floating (mandatory before
  move/resize: move on a tiled window is ignored, “No floating window found”);
- `hl.dsp.window.resize({ window = "address:0x…", x = 1100, y = 750, relative = false })`;
- `hl.dsp.window.move({ window = "address:0x…", x = 410, y = 165, relative = false })`;
- `hl.dsp.window.fullscreen({ window = "address:0x…", action = "unset" })` — unset fullscreen (otherwise
  move/resize report “Window is fullscreen”; action: toggle/set/unset);
- `hl.dsp.focus({ window = "address:0x…" })` — focus (switches to the workspace of the window);
- `hl.dsp.workspace.move({ id = 2, monitor = "DP-2" })` — switching workspaces.
- Selectors: `window = "address:0x…"`, `"class:…"`. The error “expected a dispatcher” = the name/arguments
  are not from the lua API; “hl.focus: window not found” = wrong address.
- grim: `grim -g 'X,Y WxH'` — logical coordinates; after a Hyprland restart, HYPRLAND_INSTANCE_SIGNATURE
  has to be taken again:
  `export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | head -1)`.
- Clicks/screenshots: the desktop tool click accepts **logical** coordinates (the cursor in
  `hyprctl cursorpos` is physical — ×2 at scale 2.0). For XWayland windows xdotool is more reliable
  (`DISPLAY=:0 xdotool mousemove --sync X Y; xdotool click 1`, physical coordinates).

## Maintenance: system generations and store (2026-08-21)

- odin accumulates ~200 generations per week. Cleanup keeping the last N:
  `printf 'qwe\n' | sudo -S nix-env -p /nix/var/nix/profiles/system --delete-generations 1054 1055 …`
  (or `--delete-generations +50` to “keep 50”), then `sudo nix-collect-garbage` (without -d, so that kept
  generations are not removed) — freed 8.3 GiB / 9281 paths (2026-08-21).
- The generation that contained odin2 (1237) was kept by the user — therefore odin2 lives in the store;
  GC will not clean it while 1237 is in the profile.
