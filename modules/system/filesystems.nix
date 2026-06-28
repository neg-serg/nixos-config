{ config, lib, ... }:
let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  isTelfir = config.networking.hostName == "telfir";
in
{
  boot.supportedFilesystems = [
    "btrfs"
    "exfat"
    "xfs"
    "udf"
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
      device = "/zero/music";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/torrent" = {
      device = "/zero/torrent";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/vid" = {
      device = "/zero/vid";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/games" = {
      device = "/zero/games";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/doc" = {
      device = "/zero/doc";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "/var/lib/flatpak" = {
      device = "/zero/flatpak";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.local/mail" = {
      device = "/zero/mail";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.local/share/Steam/userdata" = {
      device = "/zero/userdata_steam";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.local/share/wineprefixes" = {
      device = "/zero/wineprefixes";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };
    "${homeDir}/.cache/winetricks" = {
      device = "/zero/winetricks_cache";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
    };

    # ---- Bulk storage LVs ----

    # Old CachyOS system root (nvme0n1p4) — keep accessible for data recovery / reference
    "/mnt/cachyos" = {
      device = "/dev/nvme0n1p4";
      fsType = "xfs";
      options = [ "nofail" "x-systemd.automount" ];
    };

    # Xenon 7TiB LV (nvme2n1)
    "/mnt/xenon" = {
      device = "/dev/mapper/xenon-one";
      fsType = "xfs";
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
    { device = "/zero/swapfile"; priority = -2; }
    { device = "/swapfile"; priority = -3; size = 61440; }
  ];

  services.fstrim = lib.mkIf isTelfir { enable = true; };

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
    "d /mnt/one 0755 root root -"
  ];

  # Symlinks for convenience: /zero → /mnt/zero, /one → /mnt/one.
  # Created only when the target path doesn't already exist, so the existing
  # /zero directory (which holds bind-mount subdirs on the root fs) is preserved.
  system.activationScripts.mountSymlinks = ''
    if [ ! -e /zero ] && [ ! -L /zero ]; then
      ln -s /mnt/zero /zero
    fi
    if [ ! -e /one ] && [ ! -L /one ]; then
      ln -s /mnt/one /one
    fi
  '';
}
