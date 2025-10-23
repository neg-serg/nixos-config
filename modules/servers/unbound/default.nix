{ lib, config, pkgs, ... }:
let
  # Defaults when option set is missing (keeps evaluation safe)
  cfg = config.servicesProfiles.unbound or {
    enable = false;
    mode = "dot";
    dnssec = { enable = true; };
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
      serveExpired = { enable = true; maxTtl = 3600; replyTtl = 30; };
      cacheMinTtl = null;
      cacheMaxTtl = null;
      verbosity = 1;
      logQueries = false;
      logReplies = false;
      logLocalActions = false;
      logServfail = false;
    };
  };

  mkForwardZone =
    if cfg.mode == "dot" then {
      name = ".";
      "forward-tls-upstream" = "yes";
      forward-addr = cfg.dotUpstreams;
    } else if cfg.mode == "doh" then {
      name = ".";
      # Forward to local DoH proxy (dnscrypt-proxy2) over plaintext localhost
      forward-addr = ["127.0.0.1@5053"];
    } else null;
in {
  config = lib.mkIf cfg.enable (
    let
      yn = b: if b then "yes" else "no";
      baseServer = {
        interface = ["127.0.0.1"];
        port = 5353;
        "do-tcp" = "yes";
        "do-udp" = "yes";
        "so-reuseport" = "yes";
        "edns-buffer-size" = 1232;
        "minimal-responses" = yn cfg.tuning.minimalResponses;
        "prefetch" = yn cfg.tuning.prefetch;
        "prefetch-key" = yn cfg.tuning.prefetchKey;
        "aggressive-nsec" = yn cfg.tuning.aggressiveNsec;
        "qname-minimisation" = "yes";
        "harden-dnssec-stripped" = "yes";
        "harden-glue" = "yes";
        "harden-below-nxdomain" = "yes";
        verbosity = cfg.tuning.verbosity;
      } // lib.optionalAttrs cfg.dnssec.enable {
        "auto-trust-anchor-file" = "/var/lib/unbound/root.key";
        "val-permissive-mode" = "no";
      } // lib.optionalAttrs (cfg.mode == "dot") {
        "tls-cert-bundle" = "/etc/ssl/certs/ca-bundle.crt";
      } // lib.optionalAttrs (cfg.tuning.serveExpired.enable) {
        "serve-expired" = "yes";
        "serve-expired-ttl" = cfg.tuning.serveExpired.maxTtl;
        "serve-expired-reply-ttl" = cfg.tuning.serveExpired.replyTtl;
      } // lib.optionalAttrs (cfg.tuning.cacheMinTtl != null) {
        "cache-min-ttl" = cfg.tuning.cacheMinTtl;
      } // lib.optionalAttrs (cfg.tuning.cacheMaxTtl != null) {
        "cache-max-ttl" = cfg.tuning.cacheMaxTtl;
      } // {
        "log-queries" = yn cfg.tuning.logQueries;
        "log-replies" = yn cfg.tuning.logReplies;
        "log-local-actions" = yn cfg.tuning.logLocalActions;
        "log-servfail" = yn cfg.tuning.logServfail;
      };
    in {
      services.unbound = {
        enable = true;
        settings = {
          server = baseServer;
        } // lib.optionalAttrs (mkForwardZone != null) {
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
        } // lib.optionalAttrs (cfg.doh.sources != {}) {
          sources = cfg.doh.sources;
        };
      };
    }
  );
}
