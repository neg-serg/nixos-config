{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.brutefir # digital convolution engine for audio processing
    pkgs.camilladsp # flexible audio DSP engine for HTTP control
    pkgs.jamesdsp # audio effect processor for PipeWire and PulseAudio
    pkgs.lsp-plugins # Linux Studio Plugins collection
    pkgs.yabridge # modern and transparent VST bridge
    pkgs.yabridgectl # command-line tool for managing yabridge VSTs
  ];
}
