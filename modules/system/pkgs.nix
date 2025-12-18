{pkgs, ...}: {
  environment.systemPackages = [
    # -- Disk / Filesystem --
    pkgs.btrfs-progs # manage and check btrfs filesystems
    pkgs.cryptsetup # stuff for LUKS

    # -- Hardware Info --
    pkgs.dmidecode # extract system/memory/bios info
    pkgs.hw-probe # tool to get information about system
    pkgs.lm_sensors # Hardware monitoring sensors
    pkgs.pciutils # manipulate pci devices
    pkgs.usbutils # USB device utilities

    # -- Kernel / Boot --
    pkgs.kexec-tools # Directly boot into a new kernel

    # -- Scheduling --
    pkgs.schedtool # Query and set CPU scheduling policies
  ];
}
