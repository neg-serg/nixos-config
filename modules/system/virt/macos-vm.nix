##
# Module: system/virt/macos-vm
# Purpose: Declarative macOS VM using a dedicated QEMU systemd service.
# Key options: cfg = config.virtualisation.macosVm.*
# Dependencies: Relies on qemu-system-x86_64 from pkgs.qemu_kvm by default.
{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types;
in {
  options.virtualisation.macosVm = {
    enable = mkEnableOption "macOS VM managed by a QEMU systemd service";

    name = mkOption {
      type = types.str;
      default = "macos";
      description = "Domain name used for the macOS VM and process name.";
    };

    memoryMiB = mkOption {
      type = types.ints.positive;
      default = 8192;
      description = "Amount of RAM for the macOS VM in MiB.";
    };

    vcpus = mkOption {
      type = types.ints.positive;
      default = 4;
      description = "Number of virtual CPUs for the macOS VM.";
    };

    cpuModel = mkOption {
      type = types.str;
      default = "host";
      description = "QEMU CPU model string (for example: host, host-passthrough).";
    };

    ovmfCodePath = mkOption {
      type = types.path;
      default = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
      description = "Path to the OVMF code firmware image used for UEFI boot.";
    };

    ovmfVarsPath = mkOption {
      type = types.str;
      default = "/var/lib/libvirt/qemu/nvram/macos_VARS.fd";
      description = "Path to the writable OVMF NVRAM image for the macOS VM.";
    };

    diskImage = mkOption {
      type = types.str;
      description = "Path to the primary macOS disk image (for example, a raw or qcow2 file).";
      example = "/zero/macos-ventura.raw";
    };

    bootIsoPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional path to an installer or boot ISO (for example, OpenCore). When null, no ISO drive is attached.";
    };

    diskCache = mkOption {
      type = types.str;
      default = "none";
      description = "Cache mode for the primary disk (QEMU cache= setting).";
    };

    diskAio = mkOption {
      type = types.str;
      default = "native";
      description = "Asynchronous I/O mode for the primary disk (QEMU aio= setting).";
    };

    networkBackend = mkOption {
      type = types.enum ["user" "bridge"];
      default = "user";
      description = ''
        Network backend for the macOS VM.
        - "user": user-mode networking (NAT, no host bridge configuration required).
        - "bridge": bridge helper backend, requires a configured host bridge and qemu-bridge-helper.
      '';
    };

    bridgeName = mkOption {
      type = types.str;
      default = "br0";
      description = "Name of the host bridge interface to use when networkBackend = \"bridge\".";
    };

    videoVRAMMiB = mkOption {
      type = types.ints.positive;
      default = 256;
      description = "Amount of VRAM for virtio-vga in MiB.";
    };

    hostCPUAffinity = mkOption {
      type = types.listOf types.int;
      default = [];
      description = "Optional list of host CPU indices to pin the macOS VM process to (systemd CPUAffinity).";
    };

    extraQemuArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional QEMU CLI arguments appended as-is.";
    };

    memoryMax = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional MemoryMax limit for the macOS VM systemd service (for example, \"16G\").";
    };

    cpuWeight = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "Optional CPUWeight for the macOS VM systemd service to adjust CPU scheduling priority.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "When true, start the macOS VM automatically at boot.";
    };

    snapshotPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Optional directory where macos-vm snapshots will be stored when invoking the
        macos-vm-snapshot systemd service. Snapshotting is implemented as a simple
        copy with reflink support where available and must be triggered manually.
      '';
    };

    snapshotRetention = mkOption {
      type = types.ints.positive;
      default = 5;
      description = "Maximum number of snapshots to keep per disk image when using the macos-vm-snapshot helper.";
    };

    qemuPackage = mkOption {
      type = types.package;
      default = pkgs.qemu_kvm;
      defaultText = "pkgs.qemu_kvm";
      description = "QEMU package providing the qemu-system-x86_64 binary.";
    };
  };

  config = let
    cfg = config.virtualisation.macosVm or {enable = false;};
  in
    mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.diskImage != "";
          message = "virtualisation.macosVm.enable = true requires virtualisation.macosVm.diskImage to be set.";
        }
      ];

      # Dedicated systemd service for the macOS VM.
      systemd.services."macos-vm" = let
        qemuBin =
          lib.getExe'
          (cfg.qemuPackage or pkgs.qemu_kvm)
          "qemu-system-x86_64";

        vramBytes = cfg.videoVRAMMiB * 1024 * 1024;

        netArgs =
          if cfg.networkBackend == "bridge"
          then [
            "-device"
            "virtio-net-pci,netdev=net0"
            "-netdev"
            "bridge,id=net0,br=${cfg.bridgeName}"
          ]
          else [
            "-device"
            "virtio-net-pci,netdev=net0"
            "-netdev"
            "user,id=net0"
          ];

        baseArgs =
          [
            "-name"
            "${cfg.name},process=${cfg.name}"
            "-machine"
            "q35,accel=kvm"
            "-m"
            (builtins.toString cfg.memoryMiB)
            "-smp"
            (builtins.toString cfg.vcpus)
            "-cpu"
            cfg.cpuModel
            "-drive"
            "if=pflash,format=raw,readonly=on,file=${cfg.ovmfCodePath}"
            "-drive"
            "if=pflash,format=raw,file=${cfg.ovmfVarsPath}"
            "-drive"
            "file=${cfg.diskImage},if=virtio,cache=${cfg.diskCache},aio=${cfg.diskAio},format=raw"
          ]
          ++ netArgs
          ++ [
            "-device"
            "virtio-vga,vrambytes=${builtins.toString vramBytes}"
            "-device"
            "usb-tablet"
          ]
          ++ lib.optionals (cfg.bootIsoPath != null) [
            "-drive"
            "file=${cfg.bootIsoPath},media=cdrom,if=ide,format=raw"
          ]
          ++ cfg.extraQemuArgs;

        cmd =
          qemuBin
          + " "
          + lib.concatStringsSep " " baseArgs;
      in {
        description = "macOS VM (QEMU)";
        wantedBy =
          if cfg.autoStart
          then ["multi-user.target"]
          else [];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "simple";
          ExecStart = cmd;
          Restart = "on-failure";
          SyslogIdentifier = "macos-vm";
          # Optional CPU pinning handled via systemd.
          CPUAffinity = mkIf (cfg.hostCPUAffinity != []) cfg.hostCPUAffinity;
          MemoryMax = mkIf (cfg.memoryMax != null) cfg.memoryMax;
          CPUWeight = mkIf (cfg.cpuWeight != null) cfg.cpuWeight;
        };
      };

      # Optional snapshot helper: copies the disk image into snapshotPath with a timestamp.
      systemd.services."macos-vm-snapshot" = mkIf (cfg.snapshotPath != null) {
        description = "Create a snapshot copy of the macOS VM disk image";
        wantedBy = [];
        after = [];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = let
            snapshotScript = pkgs.writeShellScript "macos-vm-snapshot" ''
              set -eu
              target_dir='${cfg.snapshotPath}'
              src='${cfg.diskImage}'
              ts="$(date +%Y%m%d-%H%M%S)"
              base="$(basename "$src")"
              dest="$target_dir/$base.$ts"

              mkdir -p "$target_dir"
              cp --reflink=auto --sparse=always "$src" "$dest"
              keep=${toString cfg.snapshotRetention}
              if [ "$keep" -gt 0 ] 2>/dev/null; then
                cd "$target_dir"
                snaps=$(ls -1t "$base."* 2>/dev/null || true)
                if [ -n "$snaps" ]; then
                  echo "$snaps" | tail -n +$((keep + 1)) | xargs -r rm --
                fi
              fi
            '';
          in
            snapshotScript;
        };
      };
    };
}
