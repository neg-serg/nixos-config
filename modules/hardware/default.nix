# Hardware module aggregator
# Config and options moved to ./config.nix for flat-import compatibility
{ ... }:
{
  imports = [
    ./audio
    ./cpu
    ./io
    ./qmk
    ./udev-rules
    ./video
    ./webcam
    ./amdgpu.nix
    ./config.nix
    ./cooling.nix
    ./gpu-corectrl.nix
    ./liquidctl.nix
    ./pkgs.nix # Nix package manager
    ./uinput.nix
    ./usb-automount.nix
  ];
}
