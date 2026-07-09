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
  ];
  boot.initrd.supportedFilesystems = ["zfs"];
  boot.initrd.kernelModules = ["zfs"];
  boot.zfs.forceImportRoot = true;
  boot.zfs.forceImportAll = true;
  boot.zfs.extraPools = ["gamez" "bulk"];
  # Scan /dev directly — raw NVMe block devices appear at kernel probe time,
  # long before udev creates /dev/disk/by-* symlinks.
  boot.zfs.devNodes = "/dev";

  fileSystems = lib.mkIf isOdin {
    "/" = {
      device = "tank/nixos";
      fsType = "zfs";
      options = [
        "rw"
        "noatime"
        "zfsutil"
      ];
    };
    "/nix/store" = {
      device = "tank/store";
      fsType = "zfs";
      options = [
        "noatime"
        "zfsutil"
      ];
    };
    "/boot" = {
      device = "/dev/nvme0n1p5";
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

    # ZFS pools imported via boot.zfs.extraPools + devNodes=/dev
  };

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

  # Wait for raw NVMe block devices before importing non-root pools.
  systemd.services."zfs-import-gamez" = {
    bindsTo = ["dev-nvme1n1.device" "dev-nvme3n1.device"];
    after = ["dev-nvme1n1.device" "dev-nvme3n1.device"];
  };
  systemd.services."zfs-import-bulk" = {
    bindsTo = ["dev-nvme2n1.device"];
    after = ["dev-nvme2n1.device"];
  };

  # ZFS auto-scrub and trim
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  services.fstrim = lib.mkIf isOdin {enable = true;};

  # Safety net: unconditional pool import + mount after boot completes.
  boot.postBootCommands = lib.mkIf isOdin ''
    ${pkgs.zfs}/bin/zpool import -a -N || true
    ${pkgs.zfs}/bin/zfs mount -a || true
  '';

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
    "d /cache 0775 root nixbld -" # ccache for sandboxed Nix builds
  ];
}
