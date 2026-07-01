{ config, lib, pkgs, ... }:
let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  isTelfir = config.networking.hostName == "telfir";
  attrName = pkgs.zfs.kernelModuleAttribute;
  hasZfs = builtins.hasAttr attrName config.boot.kernelPackages;
in
{
  boot.supportedFilesystems = [
    "exfat"
    "xfs"
    "udf"
  ] ++ lib.optional hasZfs "zfs";

  fileSystems = lib.mkIf isTelfir {
    "/" = {
      device = "/dev/nvme0n1p2";
      fsType = "xfs";
      options = [ "rw" "relatime" "lazytime" ];
    };
    "/boot" = {
      device = "/dev/nvme0n1p5";
      fsType = "vfat";
      options = [ "x-systemd.automount" "nofail" "fmask=0177" "dmask=0077" ];
    };
    "${homeDir}/music" = {
      device = "/mnt/one/music";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/torrent" = {
      device = "/mnt/one/torrent";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/vid" = {
      device = "/mnt/one/vid";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/games" = {
      device = "/mnt/zero/games";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/doc" = {
      device = "/mnt/one/doc";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.local/mail" = {
      device = "/mnt/zero/mail";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.local/share/Steam/userdata" = {
      device = "/mnt/zero/userdata_steam";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.local/share/wineprefixes" = {
      device = "/mnt/zero/wineprefixes";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.cache/winetricks" = {
      device = "/mnt/zero/winetricks_cache";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };

    # ---- Bulk storage LVs ----

    # One 7TiB LV (nvme2n1)
    "/mnt/one" = {
      device = "/dev/mapper/xenon-one";
      fsType = "xfs";
      options = [ "nofail" "x-systemd.automount" ];
    };

    # ---- ZFS ----
    # Uncomment /tank mount and enable scrub/trim below after creating the pool:
    #   zpool create tank <devices>
    #   zfs create tank/...

    # Argon 3.6TiB LV (nvme1n1 + nvme3n1)
    "/mnt/zero" = {
      device = "/dev/mapper/argon-zero";
      fsType = "xfs";
      options = [ "nofail" "x-systemd.automount" ];
    };
  };

  swapDevices = lib.mkIf isTelfir [
    { device = "/mnt/zero/swapfile"; priority = -1; size = 102400; }
  ];

  # boot.zfs.forceImportRoot = lib.mkIf hasZfs false;

  services.fstrim = lib.mkIf isTelfir { enable = true; };
  # ZFS pool services: enable after creating the pool
  # services.zfs.autoScrub.enable = lib.mkIf hasZfs true;
  # services.zfs.trim.enable = lib.mkIf hasZfs true;

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
  ];

}
