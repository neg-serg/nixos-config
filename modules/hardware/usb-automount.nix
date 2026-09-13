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
  mountScript = pkgs.writeScriptBin "usb-mount.sh" (builtins.readFile ./usb-automount/usb-mount.sh);
in
{
  config = lib.mkIf cfg.enable {

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
