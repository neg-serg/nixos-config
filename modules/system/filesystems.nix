{ config, lib, ... }:
let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  isTelfir = config.networking.hostName == "telfir";
in
{
  boot.supportedFilesystems = [
    "exfat"
    "xfs"
    "udf"
    "zfs"
  ];

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

    "/tank" = {
      device = "tank";
      fsType = "zfs";
      options = [ "nofail" "x-systemd.automount" ];
    };

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

  boot.zfs.forceImportRoot = false;

  services.fstrim = lib.mkIf isTelfir { enable = true; };
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
  ];

}
