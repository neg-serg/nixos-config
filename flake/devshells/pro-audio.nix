{ pkgs, ... }: {
  # professional audio production environment (DAWs, editors, synths)
  nativeBuildInputs = [
    pkgs.glicol-cli # audio DSL for generative compositions
    # pkgs.ocenaudio # lightweight waveform editor — commented: fails to build (ocenaudio upstream packaging)
    pkgs.vital # spectral wavetable synth
    pkgs.flucoma # FluCoMa — corpus-based UGens for SuperCollider (analysis, ML, transformation)
    pkgs.dexed # DX7-compatible synth
    pkgs.stochas # probability-driven MIDI sequencer
    pkgs.vcv-rack # modular synth platform
    # Moved out of the system closure (2 GiB with the Faust compiler):
    # compile Faust DSP into SuperCollider UGens (faust2sc.py); also
    # `nix run .#faust2sc`.
    pkgs.faust2sc
  ];
}
