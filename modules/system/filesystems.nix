{
  config,
  lib,
  pkgs,
  ...
}:
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
  boot.initrd.supportedFilesystems = [ "zfs" ];
  boot.initrd.kernelModules = [ "zfs" ];
  boot.zfs.forceImportRoot = true;

  fileSystems = lib.mkIf isTelfir {
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
        "nofail"
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
    "${homeDir}/music" = {
      device = "/mnt/one/music";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/torrent" = {
      device = "/mnt/one/torrent";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/vid" = {
      device = "/mnt/one/vid";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/games" = {
      device = "/mnt/zero/games";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/doc" = {
      device = "/mnt/one/doc";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.local/mail" = {
      device = "/mnt/zero/mail";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.local/share/Steam/userdata" = {
      device = "/mnt/zero/userdata_steam";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.local/share/wineprefixes" = {
      device = "/mnt/zero/wineprefixes";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };
    "${homeDir}/.cache/winetricks" = {
      device = "/mnt/zero/winetricks_cache";
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
      ];
    };

    # ---- Bulk storage LVs ----

    # One 7TiB LV (nvme2n1)
    "/mnt/one" = {
      device = "/dev/mapper/xenon-one";
      fsType = "xfs";
      options = [
        "nofail"
        "x-systemd.automount"
      ];
    };

    # ---- ZFS ----

    "/tank" = {
      device = "tank";
      fsType = "zfs";
      options = [ "nofail" ];
    };

    # Argon 3.6TiB LV (nvme1n1 + nvme3n1)
    "/mnt/zero" = {
      device = "/dev/mapper/argon-zero";
      fsType = "xfs";
      options = [
        "nofail"
        "x-systemd.automount"
      ];
    };
  };

  swapDevices = lib.mkIf isTelfir [
    {
      device = "/mnt/zero/swapfile";
      priority = -1;
      size = 102400;
    }
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
    wantedBy = [ "zfs.target" ];
    after = [ "zfs.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.zfs ];
    script = ''
      if zfs list tank/nixos >/dev/null 2>&1; then
        zfs set dnodesize=auto tank/nixos
        zfs set snapshot_limit=50 tank/nixos
      fi
    '';
  };

  # ZFS auto-scrub and trim
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  services.fstrim = lib.mkIf isTelfir { enable = true; };

  systemd.tmpfiles.rules = [
    "d /boot 0700 root root -"
    "d /cache 0775 root nixbld -" # ccache for sandboxed Nix builds
  ];

  # ---- Local Nix binary cache proxy ----

  # Dataset for nginx cache storage. Created once; safe to run repeatedly.
  systemd.services.zfs-nix-cache-create = lib.mkIf isTelfir {
    description = "Create tank/nix-cache dataset if absent";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs.target" ];
    before = [ "nginx.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.zfs ];
    script = ''
      if ! zfs list tank/nix-cache >/dev/null 2>&1; then
        zfs create -o mountpoint=/tank/nix-cache \
                   -o compression=lz4 \
                   -o atime=off \
                   -o quota=150G \
                   tank/nix-cache
      fi
      mkdir -p /tank/nix-cache/nginx
    '';
  };

  # nginx reverse proxy that caches cache.nixos.org responses locally.
  # After first download, subsequent builds hit the local cache.
  services.nginx = lib.mkIf isTelfir {
    enable = true;
    recommendedProxySettings = false; # manual in nix-cache location — conflicts with cache.nixos.org Host
    recommendedOptimisation = false;
    recommendedTlsSettings = false;

    # Cache path set via extraConfig to avoid systemd CacheDirectory prefix
    commonHttpConfig = ''
      proxy_cache_path /var/cache/nginx/nix
        keys_zone=nixcache:100m
        levels=1:2
        use_temp_path=off
        inactive=30d
        max_size=100G;
    '';

    virtualHosts."nix-cache" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 3210;
        }
      ];
      serverName = "nix-cache";
      locations."/" = {
        proxyPass = "https://cache.nixos.org";
        extraConfig = ''
          # SNI обязателен — Fastly сбрасывает соединение без него
          proxy_ssl_server_name on;
          proxy_ssl_name cache.nixos.org;

          # Minimal proxy headers — Host must match cache.nixos.org
          proxy_set_header Host cache.nixos.org;

          # Force IPv4 — IPv6 is unreachable on this host
          resolver 127.0.0.1 ipv6=off valid=300s;

          proxy_cache nixcache;
          proxy_cache_key "$uri";

          # Fail fast when upstream is unreachable or slow;
          # nix will fall through to the next substituter (cache.nixos.org directly).
          proxy_connect_timeout 5s;
          proxy_read_timeout 15s;
          proxy_send_timeout 5s;

          # Prevent thundering herd on cache misses — only one request
          # per cache key goes upstream, others wait for it.
          proxy_cache_lock on;
          proxy_cache_lock_age 60s;
          proxy_cache_lock_timeout 10s;

          # Serve stale cache entry while refreshing in background
          proxy_cache_background_update on;
          proxy_cache_use_stale error timeout invalid_header updating
                              http_500 http_502 http_503 http_504 http_429;

          proxy_cache_valid 200 302 7d;
          proxy_cache_valid 404 1m;
        '';
      };
    };
  };

}
