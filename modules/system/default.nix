{inputs, ...}: {
  imports = [
    ./modules.nix
    ./preserve-flake.nix
    (inputs.self + "/modules/hardware/uinput.nix")
  ];
}
