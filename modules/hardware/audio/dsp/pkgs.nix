{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.brutefir # FIR filter
    pkgs.camilladsp # flexible audio DSP
    pkgs.jamesdsp # PipeWire DSP
    pkgs.lsp-plugins # various audio plugins
    pkgs.yabridge # VST bridge for Linux
    pkgs.yabridgectl # VST management on Linux
  ];
}
