{ inputs, ... }:
{
  imports = [
    ./boot
    ./kernel
    ./net
    ./profiles
    ./systemd
    ./virt
    ./boot.nix
    ./environment.nix
    ./filesystems.nix
    ./guix.nix
    ./irqbalance.nix
    ./oomd.nix
    ./pkgs.nix # Nix package manager
    ./preserve-flake.nix
    ./swapfile.nix
    ./tailscale.nix
    ./users.nix
    ./virt.nix
    ./winapps.nix
    ./zram.nix
    (inputs.self + "/modules/hardware/uinput.nix")
  ];
}
