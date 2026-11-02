{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Disk / Filesystem --
    pkgs.cryptsetup # stuff for LUKS

    # -- Hardware Info --
    pkgs.dmidecode # extract system/memory/bios info
    pkgs.hw-probe # tool to get information about system
    pkgs.lm_sensors # Hardware monitoring sensors
    pkgs.pciutils # manipulate pci devices
    pkgs.usbutils # USB device utilities

    # -- Kernel / Boot --
    pkgs.kexec-tools # Directly boot into a new kernel

    # -- USB / Protocol Capture --
    # Tools for the GLM/GNet protocol work (.agent/plans/2026-11-02-glm5-linux-port.md):
    # usbmon dumps land in pcap, tshark decodes the HID reports, tcpdump covers the
    # VM's network flows when a cloud step has to be traced.
    pkgs.tcpdump # packet capture CLI (usbmon pcap writing, VM network flows)
    pkgs.tshark # Wireshark CLI — decodes USB HID reports from usbmon captures

    # -- Scheduling --
    pkgs.schedtool # Query and set CPU scheduling policies

    # -- Backup --
  ];
}
