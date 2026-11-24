##
# Module: system/recovery
# Purpose: self-contained recovery environment carried on the ESP as a UKI, so
# a broken system can be repaired without booting a separate Live USB. Two entry
# points: the systemd-boot menu ("NixOS Recovery", sort-key zz-recovery) and a
# firmware boot entry ("NixOS Recovery", registered with efibootmgr) that loads
# the same EFI binary directly through systemd-stub.
#
# It is deliberately not the system's own initrd: the point is to survive the
# failures that break the normal boot chain (bad kernel/module update, broken
# initrd, a toplevel that panics). The image therefore carries its own initramfs
# with bash, the core/ZFS userspace, the ZFS/spl kernel modules built for the
# running kernel and the nvme/usb/network drivers, and drops to a root shell as
# PID 1's child - no systemd, no udev, no root mount.
#
# Boot path detail: the UKI lives outside /EFI/Linux on purpose. Files there are
# auto-discovered by systemd-boot as Type #2 entries, which would duplicate the
# explicit `recovery.conf` entry and leave its menu position to the sorting
# rules; an explicit entry keeps the sort key, and the firmware entry can point
# at the same file.
#
# The kernel modules are merged with the ZFS out-of-tree module and depmod'd
# into one tree; the archive compresses to ~95 MiB (UKI ~110 MiB). The image is
# rebuilt only when the kernel, the module set or the tool list changes, so
# unchanged inputs dedupe to the same store path.
#
# Key options: features.system.recovery.enable (default true), .pool.
# Dependencies: systemd-boot on the ESP, efibootmgr for the firmware entry,
# config.boot.zfs.package (userspace) plus the zfs-kernel module package.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.system.recovery;

  inherit (config.boot.kernelPackages) kernel;
  modDir = kernel.modDirVersion;
  kernelFile = config.system.boot.loader.kernelFile;

  # pyzfs is a propagated dependency of the zfs userspace package and pulls a
  # full Python; the recovery image only needs zpool/zfs, so drop it.
  zfsUser = config.boot.zfs.package.override { enablePython = false; };

  zfsKernel = config.boot.zfs.modulePackage;

  # One tree for depmod: the kernel's own modules plus the out-of-tree ZFS
  # module (which carries spl). Nix store paths are read-only, hence the chmod
  # between copies and before depmod writes modules.dep.
  modulesDir =
    pkgs.runCommand "recovery-modules-${modDir}"
      {
        nativeBuildInputs = [ pkgs.kmod ];
      }
      ''
        mkdir -p "$out/lib/modules/${modDir}"
        for p in ${
          lib.escapeShellArgs (
            map toString [
              kernel.modules
              zfsKernel
            ]
          )
        }; do
          [ -d "$p/lib/modules/${modDir}" ] || continue
          cp -a "$p/lib/modules/${modDir}/." "$out/lib/modules/${modDir}/"
          chmod -R u+w "$out/lib/modules/${modDir}"
        done
        depmod -b "$out" "${modDir}"
      '';

  recoveryEnter = pkgs.writeShellScriptBin "recovery-enter" ''
    set -eu
    pool="''${1:-${cfg.pool}}"
    target=/mnt

    mkdir -p "$target"
    if ${zfsUser}/bin/zpool list -H -o name "$pool" > /dev/null 2>&1; then
      echo "recovery-enter: pool '$pool' is already imported"
    else
      ${zfsUser}/bin/zpool import -R "$target" -f "$pool"
    fi
    ${zfsUser}/bin/zfs mount -a 2>/dev/null || true

    if [ ! -e "$target/nix/store" ]; then
      echo "recovery-enter: $target/nix/store is missing - import the pool with" >&2
      echo "  zpool import -R /mnt -f $pool && zfs mount -a" >&2
      exit 1
    fi

    for dir in dev proc sys; do
      ${pkgs.util-linux}/bin/mount --rbind "/$dir" "$target/$dir"
    done
    exec ${pkgs.util-linux}/bin/chroot "$target" /run/current-system/sw/bin/bash -l
  '';

  tools = pkgs.buildEnv {
    name = "recovery-tools";
    paths = [
      pkgs.bashInteractive # interactive shell (job control, readline)
      pkgs.coreutils # core userland (ls/cp/dd/uname)
      pkgs.util-linux # mount/findmnt/lsblk/chroot/setsid
      pkgs.kmod # modprobe/depmod for the module tree below
      pkgs.e2fsprogs # fsck.ext4 for filesystems on external media
      pkgs.dosfstools # fsck.vfat for the ESP
      pkgs.nvme-cli # nvme list/smart-log/format
      pkgs.smartmontools # SMART health of the drives
      pkgs.hdparm # ATA identify/spindown
      pkgs.pciutils # lspci
      pkgs.usbutils # lsusb
      pkgs.iproute2 # ip/ss
      pkgs.iputils # ping
      pkgs.dhcpcd # DHCP client for network bring-up
      pkgs.openssh # ssh/scp client
      pkgs.curl # HTTP fetches
      pkgs.rsync # copy between mounts
      pkgs.gnutar # tar
      pkgs.gzip # gzip for archives
      pkgs.zstd # zstd for archives
      pkgs.xz # xz for archives
      pkgs.less # pager
      pkgs.ncurses # `clear` and terminfo for vim/less
      pkgs.vim # editor
      pkgs.procps # ps/free/top
      pkgs.findutils # find
      pkgs.gnugrep # grep
      pkgs.gnused # sed
      pkgs.gawk # awk
      pkgs.diffutils # diff
      zfsUser # zpool/zfs userspace (pyzfs dropped, see above)
      modulesDir # kernel + zfs modules with depmod output
      recoveryEnter # recovery-enter helper (import, mount, chroot)
    ];
    pathsToLink = [
      "/bin"
      "/sbin"
      "/lib"
    ];
  };

  init = pkgs.writeScript "recovery-init" ''
    #!/bin/sh
    export PATH=/bin:/sbin
    export HOME=/root LANG=C.UTF-8

    mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
    mkdir -p /proc /sys /run /tmp /root /mnt /dev/pts
    mount -t proc proc /proc 2>/dev/null || true
    mount -t sysfs sysfs /sys 2>/dev/null || true
    mount -t devpts devpts /dev/pts 2>/dev/null || true
    mount -t tmpfs -o mode=1777 tmpfs /tmp 2>/dev/null || true
    mount -t tmpfs -o mode=0755 tmpfs /run 2>/dev/null || true

    # No udev here: load the console/disk/bus drivers explicitly, then ZFS.
    for m in nvme xhci_pci xhci_hcd usbhid hid_generic; do
      modprobe "$m" 2>/dev/null || true
    done
    if modprobe zfs 2>/dev/null; then
      echo "[recovery] zfs module loaded: $(zfs version 2>/dev/null | head -1)"
    else
      echo "[recovery] WARNING: the zfs module failed to load" >&2
    fi

    clear 2>/dev/null || true
    cat <<BANNER

      NixOS Recovery  --  $(uname -srm)

      zpool import -R /mnt -f ${cfg.pool} && zfs mount -a   # mount the system under /mnt
      recovery-enter                                       # mount it and chroot in

    BANNER

    # setsid -c gives the shell a controlling terminal (job control, Ctrl-C);
    # -w keeps PID 1 alive for as long as the shell runs.
    exec setsid -w -c bash --noprofile --norc -i < /dev/console > /dev/console 2>&1
  '';

  initrd = pkgs.makeInitrd {
    name = "recovery-initrd";
    compressor = "zstd";
    compressorArgs = [ "-10" ];
    contents = [
      {
        object = "${tools}/bin";
        symlink = "/bin";
      }
      {
        object = "${tools}/sbin";
        symlink = "/sbin";
      }
      {
        object = "${tools}/lib";
        symlink = "/lib";
      }
      {
        object = tools;
        symlink = "/usr";
      }
      {
        object = init;
        symlink = "/init";
      }
    ];
  };

  osRelease = pkgs.writeText "recovery-os-release" ''
    NAME="NixOS Recovery"
    PRETTY_NAME="NixOS Recovery"
    ID=nixos
    ID_LIKE=nixos
    VERSION="recovery"
    VERSION_ID="recovery"
  '';

  image = pkgs.runCommand "nixos-recovery.efi" { } ''
    ${pkgs.systemdUkify}/lib/systemd/ukify build \
      --linux ${kernel}/${kernelFile} \
      --initrd ${initrd}/initrd \
      --cmdline 'rdinit=/init console=tty0 console=ttyS0,115200 loglevel=4 panic=10' \
      --os-release @${osRelease} \
      --uname '${modDir}' \
      --stub ${config.systemd.package}/lib/systemd/boot/efi/linux${pkgs.stdenv.hostPlatform.efiArch}.efi.stub \
      --output $out
  '';
in
lib.mkIf (cfg.enable && config.boot.loader.systemd-boot.enable) {
  system.build.recoveryImage = image;

  boot.loader.systemd-boot.extraFiles = {
    "EFI/recovery/nixos-recovery.efi" = image;
  };

  boot.loader.systemd-boot.extraEntries = {
    "recovery.conf" = ''
      title NixOS Recovery
      efi /EFI/recovery/nixos-recovery.efi
      sort-key zz-recovery
    '';
  };

  # Register the firmware boot entry once. `extraInstallCommands` runs as root
  # from the systemd-boot installer on every switch; the label check keeps it
  # idempotent, and every failure is non-fatal (a missing NVRAM entry must not
  # abort an activation).
  boot.loader.systemd-boot.extraInstallCommands = ''
    # /boot can sit on a mount stack (systemd's autofs unit above the vfat
    # mount), so findmnt prints one source per layer: take the innermost line,
    # and keep each lsblk probe non-fatal — extraInstallCommands runs under
    # `set -eu` and must never abort an activation.
    rec_src=$(${pkgs.util-linux}/bin/findmnt -no SOURCE ${config.boot.loader.efi.efiSysMountPoint} 2>/dev/null | ${pkgs.coreutils}/bin/tail -n1) || rec_src=""
    if [ -n "$rec_src" ]; then
      rec_disk=$(${pkgs.util-linux}/bin/lsblk -no PKNAME "$rec_src" 2>/dev/null) || rec_disk=""
      rec_part=$(${pkgs.util-linux}/bin/lsblk -no PARTN "$rec_src" 2>/dev/null) || rec_part=""
      if [ -n "$rec_disk" ] && [ -n "$rec_part" ] && [ -b "/dev/$rec_disk" ]; then
        if ! ${pkgs.efibootmgr}/bin/efibootmgr 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -q 'NixOS Recovery'; then
          ${pkgs.efibootmgr}/bin/efibootmgr -q -c \
            -d "/dev/$rec_disk" -p "$rec_part" \
            -L 'NixOS Recovery' -l '\EFI\recovery\nixos-recovery.efi' \
            || echo "recovery: unable to register the UEFI boot entry" >&2
        fi
      else
        echo "recovery: cannot derive a disk/partition from $rec_src" >&2
      fi
    fi
  '';
}
