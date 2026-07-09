{
  config,
  lib,
  pkgs,
  ...
}: let
  mainUser = config.users.main.name or "neg";
  homeDir = "/home/${mainUser}";
  isOdin = config.networking.hostName == "odin";
in {
  boot.supportedFilesystems = [
    "exfat"
    "xfs"
    "udf"
    "zfs"
    "vfat"
  ];
  boot.initrd.supportedFilesystems = ["zfs" "vfat"];
  boot.initrd.kernelModules = ["zfs"];
  boot.zfs.extraPools = ["tank"]; # gamez/bulk imported after boot via systemd services
  # Scan /dev directly (raw block devices) instead of /dev/disk/by-id.
  # Raw NVMe device nodes (/dev/nvmeXn1, /dev/nvmeXn1p1) appear at kernel probe time,
  # while by-id symlinks need udev — which isn't ready yet when the import script runs.
  boot.zfs.devNodes = "/dev";



  fileSystems = lib.mkIf isOdin {
    "/" = {
      device = "tank/nixos";
      fsType = "zfs";
      options = [
        "rw"
        "noatime"
      ];
    };
    "/nix/store" = {
      device = "tank/store";
      fsType = "zfs";
      options = [
        "noatime"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/3D2F-1F3A";
      fsType = "vfat";
      options = [
        "x-systemd.automount"
        "nofail"
        "fmask=0177"
        "dmask=0077"
      ];
    };

    "${homeDir}/.local/share/Steam/userdata" = {
      device = "/gamez/main/userdata_steam";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
        "x-systemd.after=zfs.target"
      ];
    };
    "${homeDir}/.local/share/wineprefixes" = {
      device = "/gamez/main/wineprefixes";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
        "x-systemd.after=zfs.target"
      ];
    };
    "${homeDir}/.cache/winetricks" = {
      device = "/gamez/main/winetricks_cache";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
        "x-systemd.after=zfs.target"
      ];
    };

    # ZFS pools imported via boot.zfs.extraPools

    # /mnt/zero removed: argon-zero LVM volume being dismantled, replaced by ZFS pool gamez
  };

  # swapDevices = lib.mkIf isOdin [
  #   {
  #     device = "/mnt/zero/swapfile";
  #     priority = -1;
  #     size = 65536; # 64 GiB
  #   }
  # ];
  # Swap removed: /mnt/zero volume being dismantled

  # Cache both metadata and data for /nix/store — ARC has room (60 GB RAM),
  # and repeated builds read the same store paths.
  systemd.services.zfs-store-props = {
    description = "Set optimal ZFS properties on tank/store";
    wantedBy = ["zfs.target"];
    after = ["zfs.target"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [pkgs.zfs];
    script = ''
      if zfs list tank/store >/dev/null 2>&1; then
        zfs set compression=lz4 tank/store
        zfs set recordsize=128K tank/store
        zfs set atime=off tank/store
        zfs set xattr=sa tank/store
        zfs set primarycache=all tank/store
        zfs set redundant_metadata=all tank/store
        zfs set dnodesize=auto tank/store
        zfs set logbias=latency tank/store
        zfs set sync=disabled tank/store
        zfs set snapshot_limit=1000 tank/store
        zpool set autotrim=on tank
      fi
    '';
  };

  # Tune tank/nixos (root) for OS workloads and Nix xattr compatibility.
  systemd.services.zfs-nixos-props = {
    description = "Set optimal ZFS properties on tank/nixos";
    wantedBy = ["zfs.target"];
    after = ["zfs.target"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [pkgs.zfs];
    script = ''
      if zfs list tank/nixos >/dev/null 2>&1; then
        zfs set dnodesize=auto tank/nixos
        zfs set snapshot_limit=50 tank/nixos
      fi
    '';
  };

  # Non-root ZFS pool import services (imported after boot, not in initrd).
  # gamez = mirror of nvme1n1 + nvme3n1 (Samsung 990 PRO 2TB)
  # bulk  = single nvme2n1              (Samsung PM9A3 7TB)
  systemd.services."zfs-import-gamez" = {
    description = "Import ZFS pool gamez";
    wantedBy = ["multi-user.target"];
    after = ["zfs.target" "dev-nvme1n1.device" "dev-nvme3n1.device"];
    bindsTo = ["dev-nvme1n1.device" "dev-nvme3n1.device"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [pkgs.zfs];
    script = ''
      if ! zpool list gamez >/dev/null 2>&1; then
        zpool import -N gamez
      fi
      zfs mount -a
    '';
  };
  systemd.services."zfs-import-bulk" = {
    description = "Import ZFS pool bulk";
    wantedBy = ["multi-user.target"];
    after = ["zfs.target" "dev-nvme2n1.device"];
    bindsTo = ["dev-nvme2n1.device"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [pkgs.zfs];
    script = ''
      if ! zpool list bulk >/dev/null 2>&1; then
        zpool import -N bulk
      fi
      zfs mount -a
    '';
  };



  # ZFS auto-scrub and trim
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  services.fstrim = lib.mkIf isOdin {enable = true;};

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
    "d /cache 0775 root nixbld -" # ccache for sandboxed Nix builds
  ];
}
