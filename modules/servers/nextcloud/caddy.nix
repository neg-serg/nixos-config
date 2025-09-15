{
  lib,
  config,
  ...
}: let
  nc = config.services.nextcloud;
  cfg = config.services.nextcloud.caddyProxy;
  domain = nc.hostName or "localhost";
in {
  options.services.nextcloud.caddyProxy.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Serve Nextcloud via Caddy with automatic HTTPS and php_fastcgi to the Nextcloud PHP-FPM pool.
      Requires `services.nextcloud.hostName` to be a reachable DNS name.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = domain != "localhost";
        message = "Set services.nextcloud.hostName to a public or LAN DNS name when enabling caddyProxy.";
      }
      {
        assertion = !(config.services.nextcloud.nginxProxy.enable or false);
        message = "Do not enable both nginxProxy and caddyProxy at the same time.";
      }
    ];

    networking.firewall.allowedTCPPorts = [80 443];

    # Caddy manages certificates automatically; set contact email
    services.caddy = {
      enable = true;
      email = lib.mkDefault "change-me@example.com";
      virtualHosts.${domain}.extraConfig = ''
        # Nextcloud on Caddy v2
        encode zstd gzip

        # Security headers recommended by Nextcloud
        header {
          Strict-Transport-Security "max-age=15768000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          Referrer-Policy "no-referrer"
          X-XSS-Protection "1; mode=block"
          # Additional hardening
          Cross-Origin-Opener-Policy "same-origin"
          Cross-Origin-Resource-Policy "same-origin"
          X-Permitted-Cross-Domain-Policies "none"
          X-Download-Options "noopen"
          X-Robots-Tag "noindex, nofollow"
          Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=(), interest-cohort=(), fullscreen=(self), picture-in-picture=(self)"
        }

        # Well-known redirects for CalDAV/CardDAV and other discovery endpoints
        redir /.well-known/carddav /remote.php/dav 301
        redir /.well-known/caldav /remote.php/dav 301
        redir /.well-known/webfinger /index.php/.well-known/webfinger 301
        redir /.well-known/nodeinfo /index.php/.well-known/nodeinfo 301
        redir /.well-known/host-meta /public.php?service=host-meta 301
        redir /.well-known/host-meta.json /public.php?service=host-meta-json 301

        # Deny access to sensitive paths (Nextcloud hardening)
        @forbidden {
          path /.htaccess
          path /.user.ini
          path /.git*
          path /README
          path /config/*
          path /data/*
          path /build/*
          path /tests/*
          path /3rdparty/*
          path /lib/*
          path /templates/*
          path /occ
          path /console
          path /autotest*
          path /db_*
        }
        respond @forbidden 403

        # Serve Nextcloud via PHP-FPM socket provided by NixOS nextcloud module
        root * /var/lib/nextcloud
        php_fastcgi unix//run/phpfpm/nextcloud.sock
        file_server

        # LAN-only: use Caddy's internal CA to avoid public ACME attempts
        tls internal

        # Expose internal CA root for clients to download (initial trust)
        handle /ca.crt {
          root * /var/lib/caddy
          file_server
        }
      '';
    };

    # Rely on Caddy's forwarded headers for HTTPS; Nextcloud detects scheme from proxy.
    # Export Caddy internal CA root to a predictable, world-readable path
    systemd.services.caddy-export-local-ca = {
      description = "Export Caddy internal CA root to /var/lib/caddy/ca.crt";
      after = ["caddy.service"];
      requires = ["caddy.service"];
      # Defer alongside other heavy services to avoid ordering cycle with graphical.target
      wantedBy = ["post-boot.target"];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        src="/var/lib/caddy/data/caddy/pki/authorities/local/root.crt"
        dst="/var/lib/caddy/ca.crt"
        # wait up to 30s for the CA to appear on first run
        for i in $(seq 1 30); do
          if [ -s "$src" ]; then break; fi
          sleep 1
        done
        if [ -s "$src" ]; then
          install -D -m0644 -o caddy -g caddy "$src" "$dst"
        else
          echo "Caddy internal CA root not found at $src" >&2
          exit 1
        fi
      '';
    };
  };
}
