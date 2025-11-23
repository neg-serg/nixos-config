{config, ...}: let
  mainUser = config.users.main.name or "neg";
  # Avoid module eval cycles: assume default home path
  homeDir = "/home/${mainUser}";
in {
  boot.supportedFilesystems = [
    "btrfs"
    "exfat"
    "xfs"
    "udf"
  ];

  fileSystems = {
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
      # Mount /boot on-demand to avoid fsck and mount in the critical boot path
      # Tighten permissions for systemd-boot random seed (umask=0077 -> files 600, dirs 700)
      options = [
        "x-systemd.automount"
        "nofail"
        # Enforce secure perms on FAT: files 600, dirs 700
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
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/torrent" = {
      device = "/zero/torrent";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/vid" = {
      device = "/zero/vid";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/games" = {
      device = "/zero/games";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/doc" = {
      device = "/zero/doc";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "/var/lib/flatpak" = {
      device = "/zero/flatpak";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/.local/mail" = {
      device = "/zero/mail";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/.local/share/Steam/userdata" = {
      device = "/zero/userdata_steam";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/.local/share/wineprefixes" = {
      device = "/zero/wineprefixes";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
    "${homeDir}/.cache/winetricks" = {
      device = "/zero/winetricks_cache";
      options = ["bind" "nofail" "x-systemd.automount"];
    };
  };

  # Ensure swap is activated automatically at boot.
  # The file already exists at /zero/swapfile (XFS on /dev/mapper/argon-zero).
  # Systemd will order the swap unit after the mount via RequiresMountsFor=/zero.
  swapDevices = [
    {
      device = "/zero/swapfile";
      priority = -2; # match current runtime priority
    }
  ];

  # Prefer periodic TRIM over online discard for XFS on NVMe
  services.fstrim.enable = true;

  # Ensure the bare mount point has restrictive permissions even before automount
  systemd.tmpfiles.rules = [
    "d /boot 0700 root root - -"
  ];
}
