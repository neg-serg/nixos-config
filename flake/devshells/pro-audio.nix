{
  pkgs,
  ...
}:
pkgs.mkShell {
  # professional audio production environment (DAWs, editors, synths)
  nativeBuildInputs = [
    pkgs.glicol-cli # audio DSL for generative compositions
    pkgs.ocenaudio # lightweight waveform editor
    pkgs.vital # spectral wavetable synth
    pkgs.dexed # DX7-compatible synth
    pkgs.stochas # probability-driven MIDI sequencer
    pkgs.vcv-rack # modular synth platform
  ];
}
