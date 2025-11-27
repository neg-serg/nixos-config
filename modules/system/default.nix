{inputs, ...}: {
  imports = [
    ./modules.nix
    (inputs.self + "/modules/hardware/uinput.nix")
  ];
}
