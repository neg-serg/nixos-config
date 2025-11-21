##
# Module: media/audio/creation-packages
# Purpose: Provide the creative audio stack (DAWs, synths, editors) system-wide for workstation hosts.
{lib, config, pkgs, ...}: let
  enabled = config.roles.workstation.enable or false;
  packages = [
    pkgs.bespokesynth # modular DAW for live coding / patching
    pkgs.glicol-cli # audio DSL for generative compositions
    pkgs.dexed # DX7-compatible synth (LV2/VST standalone)
    pkgs.noisetorch # PulseAudio/PipeWire microphone noise gate
    pkgs.ocenaudio # lightweight waveform editor
    pkgs.reaper # flagship DAW; low latency, works great on Wine
    pkgs.rnnoise # WebRTC RNNoise denoiser CLI for mic chains
    pkgs.stochas # probability-driven MIDI sequencer
    pkgs.vcv-rack # modular synth platform
    pkgs.vital # spectral wavetable synth
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
