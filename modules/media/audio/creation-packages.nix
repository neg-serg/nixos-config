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
  enabled = config.roles.workstation.enable or false;
  tidalGhci = pkgs.writeShellScriptBin "tidal-ghci" ''
    exec ${pkgs.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@"
  '';
  packages = [
    # -- DAWs / Editors --
    pkgs.bespokesynth # modular DAW for live coding / patching
    pkgs.ocenaudio # lightweight waveform editor
    pkgs.reaper # flagship DAW; low latency, works great on Wine

    # -- Live Coding --
    pkgs.glicol-cli # audio DSL for generative compositions
    pkgs.haskellPackages.tidal # TidalCycles live-coding library
    pkgs.supercollider # SuperCollider IDE and audio engine
    pkgs.supercolliderPlugins.sc3-plugins # extra SuperCollider plugins (UGens)
    tidalGhci # GHCi wrapper with Tidal preloaded

    # -- Noise Processing --
    pkgs.noisetorch # PulseAudio/PipeWire microphone noise gate
    pkgs.rnnoise # WebRTC RNNoise denoiser CLI for mic chains

    # -- Synths / Instruments --
    pkgs.dexed # DX7-compatible synth (LV2/VST standalone)
    pkgs.stochas # probability-driven MIDI sequencer
    pkgs.vcv-rack # modular synth platform
    pkgs.vital # spectral wavetable synth
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
