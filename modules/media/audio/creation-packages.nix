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

  packages = [
    # -- DAWs / Editors --
    pkgs.bespokesynth # modular DAW for live coding / patching
  ]
  # ++ (lib.optional (config.features.media.audio.proAudio.enable or false) pkgs.reaper) # Digital audio workstation
  ++ [

    # -- Live Coding --
    pkgs.glicol-cli # audio DSL for generative compositions
    pkgs.supercollider # SuperCollider IDE and audio engine
    pkgs.supercolliderPlugins.sc3-plugins # extra SuperCollider plugins (UGens)

    # -- Noise Processing --
    pkgs.noisetorch # PulseAudio/PipeWire microphone noise gate
    pkgs.rnnoise # WebRTC RNNoise denoiser CLI for mic chains

    # -- Synths / Instruments --
    pkgs.dexed # DX7-compatible synth (LV2/VST standalone)
    pkgs.stochas # probability-driven MIDI sequencer
    # pkgs.vcv-rack # modular synth platform
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
