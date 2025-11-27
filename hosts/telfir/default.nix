{
  imports = [
    ../../profiles/desktop.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/macos.nix
    ./virtualisation/lxc.nix
  ];
}
