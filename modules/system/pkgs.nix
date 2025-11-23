{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.cryptsetup # stuff for LUKS
    pkgs.dmidecode # extract system/memory/bios info
    pkgs.hw-probe # tool to get information about system
    pkgs.kexec-tools # tools related to the kexec Linux feature
    pkgs.lm_sensors # sensors
    pkgs.pciutils # manipulate pci devices
    pkgs.schedtool # CPU scheduling
    pkgs.usbutils # lsusb
    pkgs.btrfs-progs # manage and check btrfs filesystems
  ];
}
