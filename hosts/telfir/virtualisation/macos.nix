# /etc/nixos/hosts/telfir/virtualisation/macos.nix
{ pkgs, ... }:

{
  # Enable libvirtd if it's not already enabled
  virtualisation.libvirtd.enable = true;

  virtualisation.qemu.domain."macos" = {
    enable = true;
    # Basic settings
    memory = 8192; # 8 GB RAM
    vcpu = 4;
    cpu = "host-passthrough"; # Passthrough host CPU model

    # CPU Pinning for lower latency.
    # Ensure these cores are not used by other critical tasks.
    # Check topology with `lscpu -e`.
    vcpuPin = [
      { vcpu = 0; hostcpu = 4; }
      { vcpu = 1; hostcpu = 5; }
      { vcpu = 2; hostcpu = 6; }
      { vcpu = 3; hostcpu = 7; }
    ];
    iothreads = 2;
    iothreadPin = [
      { iothread = 1; hostcpu = 8; }
      { iothread = 2; hostcpu = 9; }
    ];

    # UEFI bootloader
    boot.loader = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
    boot.loaderReadonly = true;
    # NVRAM will be created automatically
    boot.nvram = "/var/lib/libvirt/qemu/nvram/macos_VARS.fd";

    # Disks
    disk = {
      "macos-disk" = {
        # Path to the image on a separate, non-Nix managed partition
        path = "/zero/macos-ventura.raw";
        driver = "virtio-blk";
        cache = "none";
        aio = "native";
      };
      "clover" = {
        # Specify the path to your OpenCore or Clover ISO here
        path = "/path/to/your/opencore.iso";
        driver = "ide";
        cdrom = true;
        boot.index = 1; # Boot from this disk
      };
    };

    # Network
    nic.model = "virtio-net-pci";

    # Graphics (no passthrough)
    # Use VirtIO VGA for better emulated graphics performance
    video.model = "virtio-vga";
    video.vram = 256; # Increase VRAM

    # Enable tablet for correct mouse behavior without grabbing
    tablet.enable = true;
  };
}
