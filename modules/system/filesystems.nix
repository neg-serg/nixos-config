{ config, lib, pkgs, ... }:
let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  isTelfir = config.networking.hostName == "telfir";
in
{
  boot.supportedFilesystems = [ "exfat" "xfs" "udf" "zfs" ];
  boot.initrd.supportedFilesystems = [ "zfs" ];
  boot.initrd.kernelModules = [ "zfs" ];
  boot.zfs.forceImportRoot = true;

  fileSystems = lib.mkIf isTelfir {
    "/" = {
      device = "tank/nixos";
      fsType = "zfs";
      options = [ "rw" "noatime" ];
    };
    "/nix/store" = {
      device = "tank/store";
      fsType = "zfs";
      options = [ "noatime" "nofail" ];
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

  # Cache both metadata and data for /nix/store — ARC has room (60 GB RAM),
  # and repeated builds read the same store paths.
  systemd.services.zfs-store-props = {
    description = "Set optimal ZFS properties on tank/store";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.zfs ];
    script = ''
      if zfs list tank/store >/dev/null 2>&1; then
        zfs set compression=lz4 tank/store
        zfs set recordsize=128K tank/store
        zfs set atime=off tank/store
        zfs set xattr=sa tank/store
        zfs set primarycache=all tank/store
        zfs set redundant_metadata=most tank/store
        zfs set dnodesize=auto tank/store
        zfs set logbias=latency tank/store
        zfs set sync=standard tank/store
        zfs set snapshot_limit=1000 tank/store
        zfs set relatime=on tank/store
        zpool set autotrim=on tank
      fi
    '';
  };

  # ZFS auto-scrub and trim
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  services.fstrim = lib.mkIf isTelfir { enable = true; };

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
  ];

}
