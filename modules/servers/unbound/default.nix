{
  lib,
  config,
  ...
}:
let
  # Defaults when option set is missing (keeps evaluation safe)
  cfg =
    config.servicesProfiles.unbound or {
      enable = false;
      mode = "dot";
      dnssec = {
        enable = true;
      };
      dotUpstreams = [
        "1.1.1.1@853#cloudflare-dns.com"
        "1.0.0.1@853#cloudflare-dns.com"
        "9.9.9.9@853#dns.quad9.net"
        "149.112.112.112@853#dns.quad9.net"
      ];
      tuning = {
        minimalResponses = true;
        prefetch = true;
        prefetchKey = true;
        aggressiveNsec = true;
        serveExpired = {
          enable = true;
          maxTtl = 3600;
          replyTtl = 30;
        };
        cacheMinTtl = null;
        cacheMaxTtl = null;
        verbosity = 1;
        logQueries = false;
        logReplies = false;
        logLocalActions = false;
        logServfail = false;
      };
    };

  # Comss.one DNS servers (Russian privacy DNS, supports DoT)
  # https://www.comss.ru/page.php?id=7315
  comssDotUpstreams = [
    "92.223.109.31@853#comss.dns.yandex.net"
    "93.115.24.204@853#comss.dns.yandex.net"
    "91.230.211.67@853#comss.dns.yandex.net"
  ];

  # Select upstreams based on useComssDns option
  effectiveUpstreams = if (cfg.useComssDns or false) then comssDotUpstreams else cfg.dotUpstreams;

  mkForwardZone =
    if cfg.mode == "dot" then
      {
        name = ".";
        "forward-tls-upstream" = "yes";
        forward-addr = effectiveUpstreams;
      }
    else if cfg.mode == "doh" then
      {
        name = ".";
        # Forward to local DoH proxy (dnscrypt-proxy2) over plaintext localhost
        forward-addr = [ "127.0.0.1@5053" ];
      }
    else
      null;
in
{
  config = lib.mkIf cfg.enable (
    let
      baseServer = {
        interface = [ "127.0.0.1" ];
        port = 5353;
        "do-tcp" = true;
        "do-udp" = true;
        "so-reuseport" = true;
        "edns-buffer-size" = 1232;
        # Enable detailed runtime statistics for exporters (histograms, counters)
        "extended-statistics" = true;
        "statistics-interval" = 0; # disable periodic logging; exporter pulls on demand
        "statistics-cumulative" = true;
        "minimal-responses" = cfg.tuning.minimalResponses;
        "prefetch" = cfg.tuning.prefetch;
        "prefetch-key" = cfg.tuning.prefetchKey;
        "aggressive-nsec" = cfg.tuning.aggressiveNsec;
        "qname-minimisation" = true;
        "harden-dnssec-stripped" = true;
        "harden-glue" = true;
        "harden-below-nxdomain" = true;
        inherit (cfg.tuning) verbosity;
      }
      // lib.optionalAttrs cfg.dnssec.enable {
        "auto-trust-anchor-file" = "/var/lib/unbound/root.key";
        "val-permissive-mode" = false;
      }
      // lib.optionalAttrs (cfg.mode == "dot") {
        "tls-cert-bundle" = "/etc/ssl/certs/ca-bundle.crt";
      }
      // lib.optionalAttrs cfg.tuning.serveExpired.enable {
        "serve-expired" = true;
        "serve-expired-ttl" = cfg.tuning.serveExpired.maxTtl;
        "serve-expired-reply-ttl" = cfg.tuning.serveExpired.replyTtl;
      }
      // lib.optionalAttrs (cfg.tuning.cacheMinTtl != null) {
        "cache-min-ttl" = cfg.tuning.cacheMinTtl;
      }
      // lib.optionalAttrs (cfg.tuning.cacheMaxTtl != null) {
        "cache-max-ttl" = cfg.tuning.cacheMaxTtl;
      }
      // {
        "log-queries" = cfg.tuning.logQueries;
        "log-replies" = cfg.tuning.logReplies;
        "log-local-actions" = cfg.tuning.logLocalActions;
        "log-servfail" = cfg.tuning.logServfail;
      };
    in
    {
      services.unbound = {
        enable = true;
        settings = {
          server = baseServer;
          # Allow local unbound-control for Prometheus exporter without TLS certs
          "remote-control" = {
            "control-enable" = true;
            "control-interface" = "127.0.0.1";
            "control-port" = 8953;
            "control-use-cert" = false;
          };
        }
        // lib.optionalAttrs (mkForwardZone != null) {
          "forward-zone" = [ mkForwardZone ];
        };
      };

      # Optional DoH proxy via dnscrypt-proxy2 when mode = "doh"
      services.dnscrypt-proxy2 = lib.mkIf (cfg.mode == "doh") {
        enable = true;
        settings = {
          listen_addresses = [ cfg.doh.listenAddress ];
          require_dnssec = cfg.doh.requireDnssec;
          ipv6_servers = cfg.doh.ipv6Servers;
          server_names = cfg.doh.serverNames;
        }
        // lib.optionalAttrs (cfg.doh.sources != { }) {
          inherit (cfg.doh) sources;
        };
      };
    }
  );
}
