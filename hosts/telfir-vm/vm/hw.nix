{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/virtualisation/qemu-vm.nix")];

  boot = {
    # Fast-build overrides: avoid custom kernel patches/out-of-tree modules
    kernelPatches = lib.mkForce [];
    extraModulePackages = lib.mkForce [];
    # Prefer upstream latest kernel in VM
    kernelPackages = pkgs.linuxPackages_latest;
  };

  virtualisation = {
    cores = 2;
    diskSize = 10 * 1024;
    memorySize = 4 * 1024;
    qemu.options = ["-bios" "${pkgs.OVMF.fd}/FV/OVMF.fd"];
  };

  environment.systemPackages = [
    pkgs.nemu # qemu TUI interface
  ];
}
