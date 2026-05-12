##
# Module: hardware/usb-automount
# Purpose: Udev + systemd helper to auto-mount USB block devices under /mnt.
# Key options: features.hardware.usbAutomount.enable
# Dependencies: uses standard coreutils/mount; adds fs tools (btrfs/exfat/ntfs/zfs).
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.features.hardware.usbAutomount or { enable = false; };
  mountScript = pkgs.writeScriptBin "usb-mount.sh" ''
    #!/bin/sh
    PATH=$PATH:/run/current-system/sw/bin

    usage() {
        echo "Usage: $0 {add|remove} device_name (e.g. sdb1)"
        echo "$1"
        echo "$2"
        exit 1
    }

    if [ $# -ne 2 ]; then
        usage
    fi

    ACTION=$1
    DEVBASE=$2
    DEVICE="/dev/''${DEVBASE}"

    # See if this drive is already mounted, and if so where
    MOUNT_POINT=$(mount | grep ''${DEVICE} | awk '{ print $3 }')

    do_mount() {
        if [ -n ''${MOUNT_POINT} ]; then
            echo "Warning: ''${DEVICE} is already mounted at ''${MOUNT_POINT}"
            exit 1
        fi

        # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
        eval $(blkid -o udev ''${DEVICE})

        # Figure out a mount point to use
        LABEL=''${ID_FS_LABEL}
        if [ -z "''${LABEL}" ]; then
            LABEL=''${DEVBASE}
        elif grep -q " /mnt/''${LABEL} " /etc/mtab; then
            # Already in use, make a unique one
            LABEL=''${LABEL}-''${DEVBASE}
        fi
        MOUNT_POINT="/mnt/''${LABEL}"

        echo "Mount point: ''${MOUNT_POINT}"

        mkdir -p ''${MOUNT_POINT}

        # Global mount options
        OPTS="rw,noatime"

        # File system type specific mount options
        case "''${ID_FS_TYPE}" in
          vfat) OPTS="''${OPTS},users,gid=100,umask=000,shortname=mixed,utf8=1,flush" ;;
          btrfs) OPTS="''${OPTS},compress-force=zstd:3,autodefrag" ;;
          exfat) OPTS="''${OPTS},fmask=0000,dmask=0000" ;;
        esac

        if ! mount -o ''${OPTS} ''${DEVICE} ''${MOUNT_POINT}; then
            echo "Error mounting ''${DEVICE} (status = $?)"
            rmdir ''${MOUNT_POINT}
            exit 1
        fi

        echo "**** Mounted ''${DEVICE} at ''${MOUNT_POINT} ****"
    }

    do_unmount() {
        if [ -z ''${MOUNT_POINT} ]; then
            echo "Warning: ''${DEVICE} is not mounted"
        else
            umount -l ''${DEVICE}
            echo "**** Unmounted ''${DEVICE}"
        fi

        # Delete all empty dirs in /mnt that aren't being used as mount points
        for f in /mnt/*; do
            if [ -n "$(find "$f" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
                if ! grep -q " $f " /etc/mtab; then
                    echo "**** Removing mount point $f"
                    rmdir "$f"
                fi
            fi
        done
    }

    case "''${ACTION}" in
        add)
            do_mount
            ;;
        remove)
            do_unmount
            ;;
        *)
            usage
            ;;
    esac
  '';
in
{
  options.features.hardware.usbAutomount.enable = lib.mkEnableOption ''
    Enable udev-driven USB storage auto-mount via systemd service (mounts under /mnt/<label>).
  '';

  config = lib.mkIf cfg.enable {
    # Avoid double-automount with udisks/devmon
    services.devmon.enable = lib.mkForce false;

    services.udev.extraRules = ''
      KERNEL=="sd[a-z][0-9]", SUBSYSTEMS=="usb", ACTION=="add", RUN+="/bin/sh -c 'systemctl --no-block start automount-usbdrive@%k.service'"
      KERNEL=="sd[a-z][0-9]", SUBSYSTEMS=="usb", ACTION=="remove", RUN+="/bin/sh -c 'systemctl --no-block stop automount-usbdrive@%k.service'"
      KERNEL=="sd[a-z]", SUBSYSTEMS=="usb", ACTION=="add", RUN+="/bin/sh -c 'systemctl --no-block start automount-usbdrive@%k.service'"
      KERNEL=="sd[a-z]", SUBSYSTEMS=="usb", ACTION=="remove", RUN+="/bin/sh -c 'systemctl --no-block stop automount-usbdrive@%k.service'"
    '';

    systemd.services."automount-usbdrive@" = {
      description = "Automount USB Drives";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "true";
        ExecStart = "${mountScript}/bin/usb-mount.sh add %i";
        ExecStop = "${mountScript}/bin/usb-mount.sh remove %i";
      };
    };

    environment.systemPackages = lib.mkAfter [
      pkgs.exfatprogs # exfat tools
      pkgs.ntfs3g # ntfs tools
      pkgs.zfs # zfs tools
    ];
  };
}
