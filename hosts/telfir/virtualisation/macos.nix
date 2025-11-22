{
  pkgs,
  ...
}: {
  # Host-specific macOS VM description. The actual VM is managed by the
  # system-wide virtualisation.macosVm module via a dedicated QEMU service.
  #
  # To start the VM after rebuilding, use:
  #   systemctl start macos-vm.service
  virtualisation.macosVm = {
    enable = true;
    name = "macos";
    memoryMiB = 8192;
    vcpus = 4;
    cpuModel = "host-passthrough";

    # Firmware paths (OVMF code and NVRAM)
    ovmfCodePath = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
    ovmfVarsPath = "/var/lib/libvirt/qemu/nvram/macos_VARS.fd";

    # Primary disk image and optional boot ISO (for example, OpenCore)
    diskImage = "/zero/macos-ventura.raw";
    bootIsoPath = "/path/to/your/opencore.iso";

    # VRAM for virtio-vga in MiB
    videoVRAMMiB = 256;

    # Pin the VM process to a set of host CPUs.
    # This uses systemd CPUAffinity and does not attempt fine-grained
    # vCPU/iothread pinning inside QEMU.
    hostCPUAffinity = [4 5 6 7 8 9];

    # Extra QEMU arguments for better macOS ergonomics.
    # These stay generic (no Apple-specific secrets) and can
    # be further tuned or extended later.
    extraQemuArgs = [
      # Keep guest RTC in localtime; helps some desktop OSes.
      "-rtc"
      "base=localtime,clock=host,driftfix=slew"

      # Basic audio device (Intel HDA) so the guest has sound.
      "-device"
      "ich9-intel-hda"
      "-device"
      "hda-output"
    ];

    # Set to true if you want the VM to start automatically at boot.
    autoStart = false;

    # Store snapshots under /zero; snapshot helper will keep
    # at most snapshotRetention copies per disk image.
    snapshotPath = "/zero/macos-snapshots";
  };
}
