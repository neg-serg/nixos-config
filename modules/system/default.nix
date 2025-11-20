{inputs, ...}: {
  imports = [
    ./boot.nix
    ./environment.nix
    ./filesystems.nix
    ./swapfile.nix
    ./kernel/params.nix
    ./kernel/sysctl.nix
    ./kernel/sysctl-writeback.nix
    ./kernel/sysctl-mem-extras.nix
    ./kernel/sysctl-net-extras.nix
    ./kernel/patches-amd.nix
    ./profiles/security.nix
    ./profiles/performance.nix
    ./profiles/debug.nix
    (inputs.self + "/modules/hardware/uinput.nix")
    ./profiles/work.nix
    ./profiles/vm.nix
    ./profiles/aliases.nix
    ./net
    ./oomd.nix
    ./irqbalance.nix
    ./zram.nix
    ./pkgs.nix
    ./systemd
    ./users.nix
    ./virt.nix
  ];
}
