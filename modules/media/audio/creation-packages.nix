##
# Module: media/audio/creation-packages
# Purpose: Provide the creative audio stack (DAWs, synths, editors) system-wide for workstation hosts.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.creation";
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };

  # pw-jack launcher unit (lib/jack-app.nix): ExecStart under pw-jack, the
  # audio-graph ordering and the restart policy live there.
  jackApp = config.lib.neg.jackApp;

  # Renoise and Surge XT are built on first use. Surge XT is 609 MiB and is a
  # plugin, not a library every session loads — but a DAW finds plugins while
  # it scans at startup, so the Renoise launcher has to materialise the Surge
  # root and prefix the plugin paths *before* Renoise execs. The system
  # aggregation from modules/system/environment.nix stays as the tail.
  renoise = pkgs.writeShellScriptBin "renoise" ''
    set -eu
    nix=${pkgs.nix}/bin/nix
    nixStore=${pkgs.nix}/bin/nix-store
    ensure() {
      name=$1
      root="$HOME/.local/state/nix-apps/$name"
      if [ -e "$root" ]; then
        return 0
      fi
      mkdir -p "$(dirname "$root")"
      rm -f "$root"
      out=$("$nix" build --no-link --print-out-paths "git+file:///etc/nixos#$name")
      "$nixStore" --add-root "$root" --indirect --realise "$out" >/dev/null
    }
    ensure renoise
    ensure surge-xt
    surge="$HOME/.local/state/nix-apps/surge-xt"
    export LV2_PATH="$surge/lib/lv2''${LV2_PATH:+:$LV2_PATH}"
    export VST3_PATH="$surge/lib/vst3''${VST3_PATH:+:$VST3_PATH}"
    export CLAP_PATH="$surge/lib/clap''${CLAP_PATH:+:$CLAP_PATH}"
    exec "$HOME/.local/state/nix-apps/renoise/bin/renoise" "$@"
  '';

  surgeXt = onDemand {
    name = "surge-xt";
    attr = "surge-xt";
    binary = "Surge XT";
  };

  packages = [
    # -- Live Coding --
    pkgs.supercollider # SuperCollider IDE and audio engine
    pkgs.supercolliderPlugins.sc3-plugins # extra SuperCollider plugins (UGens)
    pkgs.f0plugins # redFrik SC plugins: sound chips, euclidean rhythms, wavesets (UGens)
    pkgs.steroids-ugens # SC Steroids UGens (SSinOscFB, TDemand)
    pkgs.super-bufrd # subsample-accurate buffer-reading UGens (SuperBufRd & co)
    pkgs.xplaybuf # granular playback UGen with crossfade
    pkgs.mi-ugens # Mutable Instruments eurorack modules as UGens (Clouds, Rings, …)
    pkgs.guttersynth-sc # GutterSynth UGen — coupled duffing oscillators through modal synthesis
    pkgs.my-ugens # sonoro1234 MyUGens — DWG instruments, Karplus, pitch tracking, plucked strings
    pkgs.timestretch # TimeStretch SC quark — Ness Stretch extreme time stretch
    pkgs.pitchshiftpa # PitchShiftPA SC quark — phase-aligned pitch/formant shifter
    pkgs.softcut-sc # monome Softcut multi-voice looper as SC UGen
    pkgs.signalbox # SignalBox SC quark — time/frequency-domain analysis tools
    pkgs.crucial-library # crucial-library SC quark — AbstractPlayer live-coding system
    pkgs.scmir # SCMIR — music IR analysis library (onsets, pitch, chroma) + CLI tools
    pkgs.atk-sc3 # Ambisonic Toolkit — First Order Ambisonics soundfield tools (SC quark)
    pkgs.vstplugin # host VST2/VST3 plugins inside scsynth
    pkgs.flucoma # FluCoMa — corpus-based music toolkit (57 UGens: analysis, ML, transformation)
    pkgs.safetynet # SafetyNet SC quark — protect against dangerous audio signals
    pkgs.ddwplug # ddwPlug SC quark — dynamic per-note synth patching
    pkgs.miscellaneous-lib # miSCellaneous_lib SC quark — patterns, granulation, live coding
    # faust2sc (2 GiB with the Faust compiler) moved to the `pro-audio`
    # devshell and `nix run .#faust2sc`: compile Faust DSP into SC UGens on
    # demand instead of carrying the compiler in every system activation.
    # Tidal/GHC is a 3.1G Haskell env; it lives in the `haskell` devshell and
    # this wrapper enters that shell on demand, so nvim, tidal-edit and
    # tidalctl keep finding `tidal-ghci` from any launch context.
    (pkgs.writeShellScriptBin "tidal-ghci" ''
      if [ -n "''${TIDAL_GHCI_SYSTEM:-}" ]; then
        echo "tidal-ghci: recursion guard hit — no devshell tidal-ghci on PATH" >&2
        exit 1
      fi
      export TIDAL_GHCI_SYSTEM=1
      exec ${pkgs.nix}/bin/nix develop "path:/etc/nixos#haskell" -c tidal-ghci "$@"
    '')
    pkgs.neg.tidalctl # TidalCycles session controller — engine start/stop/status, editor, recording
    pkgs.neg.superdirt # SuperDirt — sample-based SuperCollider audio engine (TidalCycles / raw SC live coding)
    # Dirt-Samples moved out of the closure: modules/media/audio/assets.nix
    # materialises it into ~/.local/state/nix-apps and supercollider.nix points
    # the SC extension symlink there (535 MiB off every switch together with
    # sc-faust and Renoise Redux).
    pkgs.pipewire.jack # PipeWire JACK compatibility (libjack.so, pw-jack) — needed by SuperCollider
    # -- Session Management --
    pkgs.new-session-manager # NSM — session manager for audio apps (JACK/PipeWire)

    # -- Patchbays & Plugin Hosts --
    pkgs.pw-audioshare # GTK4 PipeWire patchbay with auto-connect presets
    pkgs.neg.renoise-osc # OSC CLI for Renoise: renoise-osc eval '...' / renoise-reverb [--track N] [--wet X]
    pkgs.vmpk # Qt virtual MIDI keyboard (replaces GTK2 jack-keyboard) — plays into SC/VST MIDI ports
    pkgs.a2jmidid # ALSA→JACK MIDI bridge (SuperCollider MIDIOut → PipeWire → VSTs via yabridge)
    # -- Noise Processing --
    pkgs.noisetorch # PulseAudio/PipeWire microphone noise gate
    pkgs.rnnoise # WebRTC RNNoise denoiser CLI for mic chains

    # -- Pro Audio (from flake/devshells/pro-audio.nix; latency/quantum
    #    settings intentionally NOT touched) --
    pkgs.glicol-cli # audio DSL for generative compositions
    # pkgs.ocenaudio # lightweight waveform editor — commented: fails to build
    pkgs.vital # spectral wavetable synth
    pkgs.dexed # DX7-compatible FM synth
    surgeXt # open-source wavetable/VA hybrid synth (VST3/CLAP/LV2) — MPE-capable, built on first use
    pkgs.odyssey # open-source ARP Odyssey-style VA synth (VST3/LV2)
    renoise # Renoise tracker + Surge XT on LV2/VST3/CLAP paths, both built on first use
    (pkgs.makeDesktopItem {
      name = "renoise";
      desktopName = "Renoise";
      exec = "renoise %f";
      icon = "renoise";
      categories = [
        "AudioVideo"
        "Audio"
      ];
      mimeTypes = [
        "application/x-renoise-module"
        "application/x-renoise-rns-module"
      ];
    })
    pkgs.stochas # probability-driven MIDI sequencer
    pkgs.vcv-rack # modular synth platform
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;

    # Vital standalone synth — on-demand: systemctl --user start vital-standalone.
    # Runs under pw-jack (JACK via PipeWire); LIBGL_ALWAYS_SOFTWARE=1 avoids the
    # black window on Wayland/XWayland (JUCE/OpenGL rendering). Not autostarted.
    systemd.user.services.vital-standalone = jackApp.mkPwJackUnit {
      description = "Vital standalone synthesizer (pw-jack, software GL)";
      command = "${pkgs.vital}/bin/Vital";
      environment = "WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1";
    };

    # VCV Rack standalone — on-demand: systemctl --user start rack.
    # Runs under pw-jack (JACK via PipeWire) so it joins the same audio graph
    # as SuperCollider/Vital and can be patched with helvum/pw-link.
    # Not autostarted; WAYLAND_DISPLAY is required for the GLFW window on Hyprland.
    systemd.user.services.rack = jackApp.mkPwJackUnit {
      description = "VCV Rack modular synthesizer (pw-jack)";
      command = "${pkgs.vcv-rack}/bin/Rack";
      environment = "WAYLAND_DISPLAY=wayland-1";
    };
    # virtual-midi — virtual ALSA seq MIDI ports for stable synth routing
    # slots (SuperCollider connects to these instead of the hardware ports,
    # avoiding loops through the Osmose and surviving unplugs).
    systemd.user.services.virtual-midi = config.lib.neg.systemdUser.mkUserService {
      presets = [
        "audioGraph"
        "graphicalWanted"
        "restartOnFailure"
      ];
      description = "Virtual ALSA sequencer MIDI ports (synth routing slots)";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.neg.virtual-midi}/bin/virtual-midi 4";
        RestartSec = 3;
      };
    };
  };
}
