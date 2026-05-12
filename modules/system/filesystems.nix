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
      device = "/dev/mapper/main2-sys";
      fsType = "xfs";
      options = [
        "rw"
        "relatime"
        "lazytime"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/C6FE-B058";
      fsType = "vfat";
      options = [
        "x-systemd.automount"
        "nofail"
        "fmask=0177"
        "dmask=0077"
      ];
    };
    "/zero" = {
      device = "/dev/mapper/argon-zero";
      fsType = "xfs";
      options = [
        "x-systemd.automount"
        "relatime"
        "lazytime"
        "rw"
      ];
    };
    "${homeDir}/music" = {
      device = "/zero/music";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/torrent" = {
      device = "/zero/torrent";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/vid" = {
      device = "/zero/vid";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/games" = {
      device = "/zero/games";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/doc" = {
      device = "/zero/doc";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "/var/lib/flatpak" = {
      device = "/zero/flatpak";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.local/mail" = {
      device = "/zero/mail";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.local/share/Steam/userdata" = {
      device = "/zero/userdata_steam";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.local/share/wineprefixes" = {
      device = "/zero/wineprefixes";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.cache/winetricks" = {
      device = "/zero/winetricks_cache";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
  };

  swapDevices = lib.mkIf isTelfir [
    { device = "/zero/swapfile"; priority = -2; }
  ];

  services.fstrim = lib.mkIf isTelfir { enable = true; };

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
  ];
}
