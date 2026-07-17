{ inputs, ... }:
{
  imports = [
    ./boot
    ./kernel
    ./net
    ./profiles
    ./systemd
    ./vm/definitions.nix # libvirt domain XML definitions (gentoo, nixos, win11)
    ./boot.nix
    ./deduplicate-shadow.nix
    ./environment.nix
    ./filesystems.nix
    ./irqbalance.nix
    ./log-ttys.nix
    ./oomd.nix
    ./pkgs.nix # Nix package manager
    ./scx.nix
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
