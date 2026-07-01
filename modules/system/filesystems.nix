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

    "/tank" = lib.mkIf hasZfs {
      device = "tank/root";
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

  # No zfs_arc_meta_min in ZFS 2.4 — use dataset primarycache=metadata instead
  # to pin metadata in ARC. Hot data (libc, bash) won't be cached but for
  # /nix/store build workloads (read each dep once), this is optimal.

  # Optimal dataset properties for /nix/store workload:
  #   recordsize=32K — fewer block pointers per binary, faster grep/find
  #   primarycache=all — cache both metadata and hot data in ARC
  systemd.services.zfs-store-props = lib.mkIf hasZfs {
    description = "Set optimal ZFS properties on tank/store";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.zfs ];
    script = ''
      if zfs list tank/store >/dev/null 2>&1; then
        zfs set compression=lz4 tank/store
        zfs set recordsize=32K tank/store
        zfs set atime=off tank/store
        zfs set xattr=sa tank/store
        zfs set primarycache=metadata tank/store
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

  # Enable automatic ZFS snapshots for safe rollback (opt-in)
  # services.zfs.autoSnapshot = lib.mkIf hasZfs {
  #   enable = true;
  #   frequent = 4;
  #   daily = 7;
  #   weekly = 4;
  # };

  # Future: /nix/store on ZFS (uncomment after migration)
  # 1. sudo zfs create -o mountpoint=legacy tank/store
  # 2. sudo rsync -a /nix/store/ /mnt/nix-store/
  # 3. Uncomment fileSystems."/nix/store" below
  # 4. sudo reboot
  # fileSystems."/nix/store" = lib.mkIf hasZfs {
  #   device = "tank/store";
  #   fsType = "zfs";
  #   options = [ "nofail" ];
  # };

  services.fstrim = lib.mkIf isTelfir { enable = true; };
  services.zfs.autoScrub.enable = lib.mkIf hasZfs true;
  services.zfs.trim.enable = lib.mkIf hasZfs true;

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
  ];

}
