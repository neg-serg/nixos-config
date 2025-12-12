{pkgs, ...}: {
  environment.systemPackages = [
    # -- Disk / Filesystem --
    pkgs.btrfs-progs # manage and check btrfs filesystems
    pkgs.cryptsetup # stuff for LUKS

    # -- Hardware Info --
    pkgs.dmidecode # extract system/memory/bios info
    pkgs.hw-probe # tool to get information about system
    pkgs.lm_sensors # sensors
    pkgs.pciutils # manipulate pci devices
    pkgs.usbutils # lsusb

    # -- Kernel / Boot --
    pkgs.kexec-tools # tools related to the kexec Linux feature

    # -- Scheduling --
    pkgs.schedtool # CPU scheduling
  ];
}
