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
    pkgs.pipewire.jack # PipeWire JACK compatibility (libjack.so, pw-jack) — needed by SuperCollider
    # -- Session Management --
    pkgs.new-session-manager # NSM — session manager for audio apps (JACK/PipeWire)

    # -- Patchbays & Plugin Hosts --
    pkgs.carla # Full-featured JACK/PipeWire patchbay + LV2/VST plugin host
    # zestbay moved to distrobox (CXX-Qt broken in Nix): `distrobox-enter arch-zestbay -- zestbay`
    pkgs.pw-audioshare # GTK4 PipeWire patchbay with auto-connect presets
    # -- Noise Processing --
    pkgs.noisetorch # PulseAudio/PipeWire microphone noise gate
    pkgs.rnnoise # WebRTC RNNoise denoiser CLI for mic chains
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
