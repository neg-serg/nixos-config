{ config, pkgs, modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.initrd.availableKernelModules = [
    "ahci" "virtio_pci" "virtio_blk" "virtio_net" "vfat"
  ];

  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useNetworkd = true;

  fileSystems."/" = {
    device = "/dev/sda2";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/sda1";
    fsType = "vfat";
  };
}
