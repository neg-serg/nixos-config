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
    # -- Noise Processing --
    pkgs.noisetorch # PulseAudio/PipeWire microphone noise gate
    pkgs.rnnoise # WebRTC RNNoise denoiser CLI for mic chains

    # -- Pro Audio (from flake/devshells/pro-audio.nix; latency/quantum
    #    settings intentionally NOT touched) --
    pkgs.glicol-cli # audio DSL for generative compositions
    # pkgs.ocenaudio # lightweight waveform editor — commented: fails to build
    pkgs.vital # spectral wavetable synth
    pkgs.dexed # DX7-compatible FM synth
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
        Environment = "PATH=/run/current-system/sw/bin:/home/neg/.nix-profile/bin:/usr/bin:/bin";
        ExecStart = "${pkgs.distrobox}/bin/distrobox-enter arch-zestbay -- zestbay";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
