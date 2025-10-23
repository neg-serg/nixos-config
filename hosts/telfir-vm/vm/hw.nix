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

  # Keep VM base lean; omit extra packages that may fail to build with newer toolchains
  environment.systemPackages = [];

  # Prefer compressed in-RAM swap for VM workloads to avoid disk thrashing
  profiles.performance.zswap = {
    enable = true;
    compressor = "zstd";
    maxPoolPercent = 15; # 15% RAM pool cap
    zpool = "zsmalloc";
  };
}
