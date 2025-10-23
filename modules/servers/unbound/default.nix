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
      baseServer = {
        interface = ["127.0.0.1"];
        port = 5353;
        "do-tcp" = "yes";
        "do-udp" = "yes";
        "so-reuseport" = "yes";
        "edns-buffer-size" = 1232;
        "prefetch" = "yes";
        "qname-minimisation" = "yes";
        "harden-dnssec-stripped" = "yes";
        "harden-glue" = "yes";
        "harden-below-nxdomain" = "yes";
        verbosity = 1;
      } // lib.optionalAttrs cfg.dnssec.enable {
        "auto-trust-anchor-file" = "/var/lib/unbound/root.key";
        "val-permissive-mode" = "no";
      } // lib.optionalAttrs (cfg.mode == "dot") {
        "tls-cert-bundle" = "/etc/ssl/certs/ca-bundle.crt";
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
