##
# Module: system/virt/macos-vm
# Purpose: Declarative QEMU VMs managed by dedicated systemd services.
# Key options: config.virtualisation.vms.<name>.*
# Dependencies: Relies on qemu-system-x86_64 from pkgs.qemu_kvm by default.
{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types;
in {
  options.virtualisation.vms = mkOption {
    type =
      types.attrsOf (types.submodule (
        { config, name, ... }: let
          cfg = config;
          vramBytes = cfg.videoVRAMMiB * 1024 * 1024;
          monitorPath = "/run/qemu-vm-${cfg.name}.monitor";
        in {
          options = {
            enable = mkEnableOption "QEMU VM managed by a dedicated systemd service.";

            name = mkOption {
              type = types.str;
              default = name;
              description = "Domain name used for the VM and process name.";
            };

            memoryMiB = mkOption {
              type = types.ints.positive;
              default = 8192;
              description = "Amount of RAM for the VM in MiB.";
            };

            vcpus = mkOption {
              type = types.ints.positive;
              default = 4;
              description = "Number of virtual CPUs for the VM.";
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
              default = "/var/lib/libvirt/qemu/nvram/${name}_VARS.fd";
              description = "Path to the writable OVMF NVRAM image for this VM.";
            };

            diskImage = mkOption {
              type = types.str;
              description = "Path to the primary VM disk image (for example, a raw or qcow2 file).";
              example = "/zero/macos-ventura.raw";
            };

            diskFormat = mkOption {
              type = types.str;
              default = "raw";
              description = "Format of the primary VM disk image (for example, raw or qcow2).";
            };

            bootIsoPath = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional path to an installer or boot ISO (for example, OpenCore or Windows installer). When null, no ISO drive is attached.";
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

            machineType = mkOption {
              type = types.str;
              default = "q35";
              description = "QEMU machine type for the VM (for example, q35).";
            };

            accel = mkOption {
              type = types.str;
              default = "kvm";
              description = "QEMU accelerator to use for the VM (for example, kvm).";
            };

            networkBackend = mkOption {
              type = types.enum ["user" "bridge"];
              default = "user";
              description = ''
                Network backend for the VM.
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
              description = "Amount of VRAM for the primary video device in MiB.";
            };

            videoDevice = mkOption {
              type = types.str;
              default = "virtio-vga";
              description = "QEMU video device model used for the VM (for example, virtio-vga).";
            };

            hostCPUAffinity = mkOption {
              type = types.listOf types.int;
              default = [];
              description = "Optional list of host CPU indices to pin the VM process to (systemd CPUAffinity).";
            };

            extraQemuArgs = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Additional QEMU command-line arguments for this VM.";
            };

            memoryMax = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional MemoryMax limit for the VM systemd service (for example, \"16G\").";
            };

            cpuWeight = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Optional CPUWeight for the VM systemd service to adjust CPU scheduling priority.";
            };

            autoStart = mkOption {
              type = types.bool;
              default = false;
              description = "When true, start the VM automatically at boot.";
            };

            snapshotPath = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Optional directory where VM snapshots will be stored when invoking the
                qemu-vm-<name>-snapshot systemd service. Snapshotting is implemented as a simple
                copy with reflink support where available and must be triggered manually.
              '';
            };

            snapshotRetention = mkOption {
              type = types.ints.positive;
              default = 5;
              description = "Maximum number of snapshots to keep per disk image when using the VM snapshot helper.";
            };

            qemuPackage = mkOption {
              type = types.package;
              default = pkgs.qemu_kvm;
              defaultText = "pkgs.qemu_kvm";
              description = "QEMU package providing the qemu-system-x86_64 binary.";
            };
          };

          config = mkIf cfg.enable {
            assertions = [
              {
                assertion = cfg.diskImage != "";
                message = "virtualisation.vms.${name}.enable = true requires virtualisation.vms.${name}.diskImage to be set.";
              }
            ];

            # Dedicated systemd service for the VM.
            systemd.services."qemu-vm-${cfg.name}" = let
              qemuBin =
                lib.getExe'
                (cfg.qemuPackage or pkgs.qemu_kvm)
                "qemu-system-x86_64";

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
                  "${cfg.machineType},accel=${cfg.accel}"
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
                  "file=${cfg.diskImage},if=virtio,cache=${cfg.diskCache},aio=${cfg.diskAio},format=${cfg.diskFormat}"
                  "-monitor"
                  "unix:${monitorPath},server,nowait"
                ]
                ++ netArgs
                ++ [
                  "-device"
                  "${cfg.videoDevice},vrambytes=${builtins.toString vramBytes}"
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

              gracefulShutdownScript =
                pkgs.writeShellScript "qemu-vm-${cfg.name}-shutdown" ''
                  #!/bin/sh
                  sock='${monitorPath}'
                  if [ -S "$sock" ]; then
                    printf 'system_powerdown\n' | ${pkgs.socat}/bin/socat - "UNIX-CONNECT:$sock" || true
                  fi
                '';
            in {
              description = "QEMU VM (${cfg.name})";
              wantedBy =
                if cfg.autoStart
                then ["multi-user.target"]
                else [];
              after = ["network-online.target"];
              wants = ["network-online.target"];
              serviceConfig = {
                Type = "simple";
                ExecStart = cmd;
                ExecStop = gracefulShutdownScript;
                Restart = "on-failure";
                SyslogIdentifier = "qemu-vm-${cfg.name}";
                # Optional CPU pinning handled via systemd.
                CPUAffinity = mkIf (cfg.hostCPUAffinity != []) cfg.hostCPUAffinity;
                MemoryMax = mkIf (cfg.memoryMax != null) cfg.memoryMax;
                CPUWeight = mkIf (cfg.cpuWeight != null) cfg.cpuWeight;
              };
            };

            # Optional snapshot helper: copies the disk image into snapshotPath with a timestamp.
            systemd.services."qemu-vm-${cfg.name}-snapshot" = mkIf (cfg.snapshotPath != null) {
              description = "Create a snapshot copy of the VM disk image";
              wantedBy = [];
              after = [];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = let
                  snapshotScript = pkgs.writeShellScript "qemu-vm-${cfg.name}-snapshot" ''
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
      ));

    default = {};
    description = "Set of QEMU VMs managed by dedicated systemd services.";
  };
}

