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
    pkgs.nn-ar # nn.ar — neural audio UGens (PyTorch models in scsynth)
    pkgs.flucoma # FluCoMa — corpus-based music toolkit (57 UGens: analysis, ML, transformation)
    pkgs.safetynet # SafetyNet SC quark — protect against dangerous audio signals
    pkgs.ddwplug # ddwPlug SC quark — dynamic per-note synth patching
    pkgs.miscellaneous-lib # miSCellaneous_lib SC quark — patterns, granulation, live coding
    pkgs.faust2sc # compile Faust DSP into SuperCollider UGens (faust2sc.py)
    pkgs.neg.superdirt # SuperDirt — SuperCollider audio engine (SC quark, used by raw SC live coding)
    pkgs.neg.dirt-samples # SuperDirt audio sample library
    pkgs.pipewire.jack # PipeWire JACK compatibility (libjack.so, pw-jack) — needed by SuperCollider
    # -- Session Management --
    pkgs.new-session-manager # NSM — session manager for audio apps (JACK/PipeWire)

    # -- Patchbays & Plugin Hosts --
    # zestbay moved to distrobox (CXX-Qt broken in Nix): `distrobox-enter arch-zestbay -- zestbay`
    pkgs.pw-audioshare # GTK4 PipeWire patchbay with auto-connect presets
    pkgs.neg.zest # CLI for ZestBay plugin management: zest list/add/rm/ls
    pkgs.neg.midi-transcribe # audio->MIDI transcription: midi-transcribe <file.mp3> (hFT-Transformer, CPU)
    pkgs.jack-keyboard # virtual MIDI keyboard for JACK/PipeWire — plays into SC/VST MIDI ports
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
    pkgs.surge-xt # open-source wavetable/VA hybrid synth (VST3/CLAP/LV2) — MPE-capable
    pkgs.odyssey # open-source ARP Odyssey-style VA synth (VST3/LV2)
    (pkgs.reaper.override {
      # reaper.fm is blocked/slow from this host — vendor the binary tarball
      # in files/sources (fetched via the proxy). Match ANY reaper.fm linux
      # tarball URL (nixpkgs bumps the version, e.g. reaper773 -> reaper778;
      # the vendored 7.73 source is used for whatever version nixpkgs wants).
      fetchurl =
        args:
        if
          builtins.match "https://www.reaper.fm/files/.*/reaper[0-9]+_linux_x86_64.tar.xz" (args.url or "")
          != null
        then
          (pkgs.runCommand "reaper-src.tar.xz" { } ''
            cp ${../../../files/sources/reaper773_linux_x86_64.tar.xz} $out
          '')
        else
          pkgs.fetchurl args;
      # Skip ffmpeg (video import) and VLC: their sources are blocked or
      # build for a long time from source; audio use does not need them.
      # (nixos-unstable renamed reaper's `ffmpeg_4-headless` arg to `ffmpeg-headless`.)
      "ffmpeg-headless" = null;
      vlc = null;
    }) # DAW (Linux native) — portable config, scriptable via ReaScript/OSC
    pkgs.stochas # probability-driven MIDI sequencer
    pkgs.vcv-rack # modular synth platform
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;

    # ZestBay (patchbay + LV2/CLAP/VST3 plugin host) autostart at login.
    # Runs inside the arch distrobox container; keeps learned auto-connect
    # rules and the plugin chain alive so no manual wiring is needed.
    # Tray mode: Preferences → "start minimized" / "close to tray" (stored in
    # ~/.config/zestbay/preferences.json).
    systemd.user.services.zestbay = {
      description = "ZestBay PipeWire patchbay and plugin host (distrobox)";
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        # distrobox-enter needs podman/docker on PATH; systemd-user may not
        # carry /run/current-system/sw/bin when the unit starts, which makes
        # distrobox fail with "Missing dependency: we need a container manager".
        # /run/wrappers/bin must come first: rootless podman needs the setuid
        # newuidmap wrapper, otherwise "newuidmap: Operation not permitted".
        # Without WAYLAND_DISPLAY Qt falls back to the offscreen platform: the
        # event loop runs but no window is ever shown (Hyprland socket wayland-1).
        Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/home/neg/.nix-profile/bin:/usr/bin:/bin WAYLAND_DISPLAY=wayland-1";
        ExecStart = "${pkgs.distrobox}/bin/distrobox-enter arch-zestbay -- zestbay";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Vital standalone synth — on-demand: systemctl --user start vital-standalone.
    # Runs under pw-jack (JACK via PipeWire); LIBGL_ALWAYS_SOFTWARE=1 avoids the
    # black window on Wayland/XWayland (JUCE/OpenGL rendering). Not autostarted.
    systemd.user.services.vital-standalone = {
      description = "Vital standalone synthesizer (pw-jack, software GL)";
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      serviceConfig = {
        Type = "simple";
        Environment = "WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1";
        ExecStart = "${pkgs.pipewire.jack}/bin/pw-jack ${pkgs.vital}/bin/Vital";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    # VCV Rack standalone — on-demand: systemctl --user start rack.
    # Runs under pw-jack (JACK via PipeWire) so it joins the same audio graph
    # as SuperCollider/Vital and can be patched with helvum/pw-link.
    # Not autostarted; WAYLAND_DISPLAY is required for the GLFW window on Hyprland.
    systemd.user.services.rack = {
      description = "VCV Rack modular synthesizer (pw-jack)";
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      serviceConfig = {
        Type = "simple";
        Environment = "WAYLAND_DISPLAY=wayland-1";
        ExecStart = "${pkgs.pipewire.jack}/bin/pw-jack ${pkgs.vcv-rack}/bin/Rack";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
    # virtual-midi — virtual ALSA seq MIDI ports for stable synth routing
    # slots (SuperCollider connects to these instead of the hardware ports,
    # avoiding loops through the Osmose and surviving unplugs).
    systemd.user.services.virtual-midi = {
      description = "Virtual ALSA sequencer MIDI ports (synth routing slots)";
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.neg.virtual-midi}/bin/virtual-midi 4";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
