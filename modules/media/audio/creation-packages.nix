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
    pkgs.haskellPackages.tidal # TidalCycles live coding environment (SuperCollider-based)
    pkgs.neg.superdirt # SuperDirt — TidalCycles audio engine (SC quark)
    pkgs.neg.dirt-samples # SuperDirt audio sample library
    pkgs.tidal-ghci # GHCi with TidalCycles preloaded (for tidal.nvim)
    pkgs.neg.tidalctl # TidalCycles session controller — engine start/stop/status, editor, recording
    pkgs.pipewire.jack # PipeWire JACK compatibility (libjack.so, pw-jack) — needed by SuperCollider
    # -- Session Management --
    pkgs.new-session-manager # NSM — session manager for audio apps (JACK/PipeWire)

    # -- Patchbays & Plugin Hosts --
    pkgs.carla # Full-featured JACK/PipeWire patchbay + LV2/VST plugin host
    # zestbay moved to distrobox (CXX-Qt broken in Nix): `distrobox-enter arch-zestbay -- zestbay`
    pkgs.pw-audioshare # GTK4 PipeWire patchbay with auto-connect presets
    pkgs.neg.zest # CLI for ZestBay plugin management: zest list/add/rm/ls
    pkgs.neg.carlactl # console VST router via headless Carla: carlactl list/run/route
    pkgs.jack-keyboard # virtual MIDI keyboard for JACK/PipeWire — plays into Carla/VST MIDI ports
    pkgs.a2jmidid # ALSA→JACK MIDI bridge (SuperCollider MIDIOut → PipeWire → Carla/VSTs)
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
    (pkgs.reaper.override {
      # ffmpeg_4-headless (4.4.8) pulls a source whose host answers an
      # anti-bot page (Anubis) — use the current ffmpeg-headless instead.
      "ffmpeg_4-headless" = pkgs.ffmpeg-headless;
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
