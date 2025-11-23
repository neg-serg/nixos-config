##
# Module: profiles/services
# Purpose: Central registry of profiles.services.* options (alias servicesProfiles.*).
# Key options: cfg = config.servicesProfiles.<service> (enable and service-specific settings).
# Dependencies: Referenced by service modules under modules/servers/*.
{
  lib,
  pkgs,
  inputs,
  ...
}: let
  inherit (lib) types;
  opts = import (inputs.self + "/lib/opts.nix") {inherit lib;};
in {
  options.servicesProfiles = {
    adguardhome = {
      enable = opts.mkEnableOption "AdGuard Home DNS with rewrites/profile wiring.";
      # Optional filter list catalog to be written into AdGuardHome.yaml
      filterLists =
        opts.mkListOpt (types.submodule (_: {
          options = {
            name = opts.mkStrOpt {description = "Human-friendly filter list name";};
            url = opts.mkStrOpt {description = "URL to the filter list";};
            enabled = opts.mkBoolOpt {
              default = true;
              description = "Enable this list";
            };
          };
        })) {
          default = [];
          description = "List of upstream filter lists for AdGuardHome.";
          example = [
            {
              name = "AdGuard DNS filter";
              url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
            }
          ];
        };
      rewrites =
        opts.mkListOpt (types.submodule (_: {
          options = {
            domain = opts.mkStrOpt {description = "Domain to rewrite";};
            answer = opts.mkStrOpt {description = "Rewrite answer (IP or hostname)";};
          };
        })) {
          default = [];
          description = "List of DNS rewrite rules for AdGuard Home.";
          example = [
            {
              domain = "nas.local";
              answer = "192.168.1.10";
            }
          ];
        };
    };
    bitcoind = {
      enable = opts.mkEnableOption "Bitcoin Core node profile with a custom data directory.";
      instance = opts.mkStrOpt {
        default = "main";
        description = "Instance name used under services.bitcoind.<name>.";
        notes = "The resulting systemd unit runs as bitcoind-<name>.";
      };
      dataDir = opts.mkStrOpt {
        default = "/zero/bitcoin-node";
        description = "Filesystem path for the Bitcoin Core data directory.";
        notes = "The directory is created automatically with the correct ownership when the profile is enabled.";
      };
      p2pPort = opts.mkIntOpt {
        default = 8333;
        description = "TCP port to expose for Bitcoin peer-to-peer traffic.";
        notes = "Set this to 18333 for testnet or another value if you override the service port.";
      };
    };
    unbound = {
      enable = opts.mkEnableOption "Unbound DNS resolver profile.";
      mode = opts.mkEnumOpt ["recursive" "dot" "doh"] {
        default = "dot";
        description = "How Unbound fetches upstream DNS: direct recursion, DNS-over-TLS, or via DoH proxy.";
      };
      dnssec = {
        enable = opts.mkBoolOpt {
          default = true;
          description = "Enable DNSSEC validation in Unbound.";
        };
      };
      tuning = {
        # Response/validation behavior
        minimalResponses = opts.mkBoolOpt {
          default = true;
          description = "Prefer minimal responses to reduce packet sizes (Unbound: minimal-responses).";
        };
        prefetch = opts.mkBoolOpt {
          default = true;
          description = "Enable prefetch of expiring records (Unbound: prefetch).";
        };
        prefetchKey = opts.mkBoolOpt {
          default = true;
          description = "Prefetch DNSKEY/DS (Unbound: prefetch-key).";
        };
        aggressiveNsec = opts.mkBoolOpt {
          default = true;
          description = "Synthesize NXDOMAIN/NOERROR/NODATA from NSEC/NSEC3 (Unbound: aggressive-nsec).";
        };
        serveExpired = {
          enable = opts.mkBoolOpt {
            default = true;
            description = "Serve expired records while refreshing in background (Unbound: serve-expired).";
          };
          # Max seconds since expiration to serve stale answers
          maxTtl = opts.mkIntOpt {
            default = 3600;
            description = "Maximum seconds to serve expired data (Unbound: serve-expired-ttl).";
          };
          # TTL of the served expired reply
          replyTtl = opts.mkIntOpt {
            default = 30;
            description = "TTL in seconds used on served-expired replies (Unbound: serve-expired-reply-ttl).";
          };
        };
        # Cache TTL guards (null = do not set)
        cacheMinTtl = opts.mkOpt (types.nullOr types.int) null {
          description = "Minimum TTL to apply to cache entries (Unbound: cache-min-ttl).";
          defaultText = "null (use Unbound default)";
        };
        cacheMaxTtl = opts.mkOpt (types.nullOr types.int) null {
          description = "Maximum TTL to apply to cache entries (Unbound: cache-max-ttl).";
          defaultText = "null (use Unbound default)";
        };
        # Logging
        verbosity = opts.mkIntOpt {
          default = 1;
          description = "Unbound log verbosity (0–5).";
        };
        logQueries = opts.mkBoolOpt {
          default = false;
          description = "Enable query logging (Unbound: log-queries). Heavy; keep off by default.";
        };
        logReplies = opts.mkBoolOpt {
          default = false;
          description = "Enable reply logging (Unbound: log-replies).";
        };
        logLocalActions = opts.mkBoolOpt {
          default = false;
          description = "Log local actions (cache, validation) (Unbound: log-local-actions).";
        };
        logServfail = opts.mkBoolOpt {
          default = false;
          description = "Log SERVFAIL responses (Unbound: log-servfail).";
        };
      };
      dotUpstreams = opts.mkListOpt types.str {
        default = [
          "1.1.1.1@853#cloudflare-dns.com"
          "1.0.0.1@853#cloudflare-dns.com"
          "9.9.9.9@853#dns.quad9.net"
          "149.112.112.112@853#dns.quad9.net"
        ];
        description = "List of DoT forwarders in host@port#SNI format.";
      };
      doh = {
        listenAddress = opts.mkStrOpt {
          default = "127.0.0.1:5053";
          description = "Local address where dnscrypt-proxy2 (DoH proxy) listens.";
        };
        serverNames = opts.mkListOpt types.str {
          default = ["cloudflare" "quad9-doh"];
          description = "dnscrypt-proxy2 server_names to use for DoH.";
        };
        ipv6Servers = opts.mkBoolOpt {
          default = false;
          description = "Allow IPv6 upstream servers in dnscrypt-proxy2.";
        };
        requireDnssec = opts.mkBoolOpt {
          default = true;
          description = "Require DNSSEC-capable upstreams in dnscrypt-proxy2.";
        };
        sources = opts.mkOpt types.attrs {} {
          description = "Optional dnscrypt-proxy2 sources object to override default public-resolvers.";
          example = {
            public-resolvers = {
              urls = [
                "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
                "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
              ];
              cache_file = "/var/lib/dnscrypt-proxy2/public-resolvers.md";
            };
          };
        };
      };
    };
    openssh.enable = opts.mkEnableOption "OpenSSH (and mosh) profile.";
    mpd.enable = opts.mkEnableOption "MPD (Music Player Daemon) profile.";
    nextcloud = {
      enable = opts.mkEnableOption "Nextcloud server profile (with optional Caddy proxy).";
      package = opts.mkOpt (types.nullOr types.package) null {
        description = ''
          Nextcloud package derivation to use for the service.
          Set to a specific `pkgs.nextcloudXX` or a flake-provided package to pin the major version.
          When unset, the module uses a sensible default from `pkgs` (currently Nextcloud 31).
        '';
        example = pkgs.nextcloud31;
      };
    };
    avahi.enable = opts.mkEnableOption "Avahi (mDNS) profile.";
    jellyfin.enable = opts.mkEnableOption "Jellyfin media server profile.";
    samba.enable = opts.mkEnableOption "Samba (SMB/CIFS) fileshare profile.";
    seafile = {
      enable = opts.mkEnableOption "Seafile file sync and sharing server profile (Podman containers + optional Caddy proxy).";
      hostName = opts.mkStrOpt {
        default = "localhost";
        description = "Public host name for Seafile, used by clients and reverse proxy.";
      };
      dataDir = opts.mkStrOpt {
        default = "/seafile";
        description = "Host directory for Seafile data (shared volume mapped into the main container).";
      };
      adminEmail = opts.mkStrOpt {
        default = "admin@example.com";
        description = "Initial Seafile admin account email.";
      };
      adminPassword = opts.mkStrOpt {
        default = "change-me";
        description = "Initial Seafile admin account password (used for SEAFILE_ADMIN_PASSWORD).";
      };
      dbRootPassword = opts.mkStrOpt {
        default = "change-me";
        description = "MariaDB root password used by the Seafile stack (DB_ROOT_PASSWD / MYSQL_ROOT_PASSWORD).";
      };
      httpPort = opts.mkIntOpt {
        default = 8082;
        description = "Local TCP port where the Seafile HTTP endpoint is exposed (proxied by Caddy when enabled).";
      };
      useCaddy = opts.mkBoolOpt {
        default = true;
        description = "Serve Seafile via Caddy with automatic HTTPS on hostName.";
      };
    };
  };
}
