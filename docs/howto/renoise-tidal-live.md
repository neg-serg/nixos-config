# Renoise + TidalCycles: daily live-coding workflow on odin

A short cheat sheet for music sessions. Both stacks live in the system declaratively
(NixOS + nix-maid); below are the commands, ports and gotchas you hit in practice.

## Quick-start commands (Justfile)

    just renoise        # Renoise under pw-jack (JACK driver into the shared PipeWire graph)
    just tidal-start    # SuperDirt engine (sclang + scsynth), waits up to 120 s for readiness
    just tidal-status   # processes, OSC ports, audio links
    just tidal-demo     # engine + demo scene in nvim
    just tidal-record   # record SuperDirt → ~/src/art/music/tidal/recordings/
    just tidal-edit     # workspace + ghci terminal (tidal-ghci) in nvim
    just tidal-monitor  # pw-top
    just renoise-osc    # OSC CLI for Renoise (renoise-osc help / --help)
    just renoise-record # capture Renoise audio to wav (see Recording)

Raw SuperCollider (scnvim, no Tidal): hotkey M4+Shift+t → sc-live (live.scd,
s.boot in the session). Renoise/plugins: synth LegendHZ, synth Surge_XT, …; the
Renoise class always sits on workspace 12 "daw". Launching Renoise itself (run-or-raise):
M4+Shift+a focuses the open Renoise window or starts it.

## Don't start both engines at the same time

Both use the SuperCollider ports 57110 (scsynth) / 57120 (OSC SuperDirt):

- Tidal session: tidalctl start brings up headless sclang + SuperDirt
  (log: ~/.local/state/tidalctl/engine.log, readiness marker
  SUPERDIRT READY). Then nvim with a .tidal file: <leader>tl (launch
  Tidal/ghci), <M-CR>/<leader>ts (send pattern), <leader>tb (whole
  buffer), <leader>th (hush), <leader>tq (quit).
- Raw-SC session: do NOT start tidalctl; sc-live runs s.boot itself inside
  the scnvim session (sclang-pwj).

## Renoise OSC (remote control from the shell)

Renoise OSC server: UDP 127.0.0.1:9002 (Udp protocol). Ports 9000/UDP are taken by
glm-osc (Genelec SAM) — do not point Renoise back at 9000.

    renoise-osc-config            # write into Config.xml: enabled/Udp/9002 (Renoise must be closed!)
    renoise-osc status            # is Renoise running? is the port listening?
    renoise-osc transport start|stop|continue|panic|toggle
    renoise-osc bpm 128           # tempo (20–999); lpb 1–255; tpl 1–16
    renoise-osc loop pattern on   # loop the pattern / loop block on|off
    renoise-osc loop sequence 1 8 # loop range over the sequence
    renoise-osc track 1 mute|unmute|solo
    renoise-osc track 1 volume 0.8 | volume-db -6 | pan 0.5
    renoise-osc instr 1 volume-db -3 | transpose 12 | macro 3 0.5
    renoise-osc device 1 1 bypass on     # track, device, on|off
    renoise-osc record [--secs 30] [--target renoise] [--out FILE]
    renoise-osc eval '…lua…'      # arbitrary Lua via /renoise/evaluate
    renoise-osc reverb [--track master|N] [--wet X]
    renoise-osc load 'Legend HZ'  # new instrument + VST (starts Renoise itself if needed)
    renoise-osc help <cmd>        # extended help for a command
    renoise-osc --dry <cmd> …     # show the OSC message without sending it

The commands wrap the documented addresses from GlobalOscActions.lua
(shipped with Renoise): transport/loop, song/bpm|lpb|tpl, track/instrument/device
parameters. The server sends no responses (fire-and-forget); eval errors are visible in
the Renoise scripting console.

## Paths and workspaces (canon)

- Session workspace: ~/src/art/music/tidal/ (tt.tidal, demo.tidal, recordings/,
  samples/). Real projects are the files next to them in this directory.
- Journey files are symlinked into the private ~/notes/music/tidal/
  (BootTidal.hs, demo.tidal, scratch.tidal) and ~/notes/music/supercollider/
  (superdirt_startup.scd, etc.) — the user edits them; the notes repo does
  the git versioning.
- Boot: ~/.config/tidal/BootTidal.hs → notes. SuperDirt startup:
  ~/.config/SuperCollider/superdirt_startup.scd → notes (samples/buffers load
  there too: piano162, acoustic, vsco_strings, winds, IR).
- ghci/tidal: the tidal-ghci wrapper from systemPackages (GHC + TidalCycles);
  tidal-edit opens it in an nvim terminal.

## Audio/MIDI

- Sink game-stereo (48 kHz / quantum 256) → RME AES (AUX0/1). Renoise/SuperCollider
  port links into game-stereo are kept by the user services
  renoise-link.service and supercollider-link.service.
- MIDI: physical RME keyboard → Renoise; SC→Renoise via midi-bridge;
  virtual-midi out0-3 — stable slots for synths; glm-midi — Genelec GLM
  over rtpMIDI (see windows-vm-dockur.md).

## Recording and rendering in Renoise

Renoise is a tracker without audio tracks, so "recording" comes in two kinds.

**1) Offline song render (best quality, final mix).**
Menu File → Export Audio…: you pick the format (WAV/FLAC/OGG), sample rate
(48 kHz), bit depth, loudness/normalization; the whole song is rendered (or a
selected range/tracks). This is done in the GUI — there is no export in the OSC/Lua API.

**2) Live session capture (what actually sounds, including live inputs).**
Renoise audio is auto-linked into the game-stereo sink (renoise-link service), so:

    just renoise-record                  # into ~/src/art/music/renoise/recordings/
    renoise-osc record --secs 30         # the same 30 seconds
    renoise-osc record --target renoise  # only Renoise, without the rest of the mix
    renoise-osc record --out ~/x.wav     # your own path (pw-record under the hood)

Stop: Ctrl+C or cap it with --secs. A SuperDirt session is recorded the same way:
just tidal-record (into ~/src/art/music/tidal/recordings/); any stream —
sc-record <secs> or pw-record --target playback.game-stereo.

## Gotchas (verified)

1. tidalctl/tidal-ghci not found → previous system generations were GC'd:
   run nh os switch /etc/nixos#odin --option substitute false (packages are in
   systemPackages). Do not keep store paths in hand-written scripts — PATH only.
2. Renoise OSC is silent → Config.xml is corrupted (for example after editing it in
   the GUI): close Renoise and run renoise-osc-config; then check renoise-osc status.
3. No sound from Renoise → the renoise-link service must be active
   (systemctl --user status renoise-link); the JACK ports are named
   renoise:output_01_left/right.
4. Engine.log: no synth or sample named 'p162' → the pattern uses a nonexistent
   instrument/sample name (the piano162 buffer loads, but the SynthDef is named
   differently) — fix the pattern or superdirt_startup.scd, then run
   tidalctl restart.
5. Demo songs from /nix/store cannot be opened (backup errors on autosave) —
   work with projects in ~/src/art/music/tidal or ~/notes/music/renoise.
6. The NeuralTranscribe tool (Tools → Neural MIDI Transcription): loads after the
   strict-global guard fix (rawget); MIDI import errors go to
   ~/.local/share/renoise-neural/.
7. tidalctl start crashes with qt.qpa/xcb (SuperDirtMixer wants Qt, but the launch
   has no display): the new version sets QT_QPA_PLATFORM=offscreen by itself when
   WAYLAND_DISPLAY/DISPLAY are absent — just update the system.

## Links

- Windows VSTs via yabridge: wine-vst-bridge.md
- Local neural nets/recognition: local-music-ai.md, neural-stack-report.md
- Renoise OSC API: https://tutorials.renoise.com/wiki/Open_Sound_Control
