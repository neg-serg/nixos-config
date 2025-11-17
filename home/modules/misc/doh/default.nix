{
  lib,
  config,
  options,
  ...
}:
with lib; let
  hmEval = config ? home;
  dohEnabled = config.features.network.doh.enable;
  dnscryptAvailable =
    if hmEval
    then false
    else (options ? services) && (options.services ? dnscrypt-proxy2);
  networkingAvailable =
    if hmEval
    then false
    else options ? networking;
  warningMessages =
    lib.optional (dohEnabled && !dnscryptAvailable)
      "features.network.doh.enable is set, but services.dnscrypt-proxy2 is unavailable in this evaluation. Import this module from a NixOS system configuration."
    ++ lib.optional (dohEnabled && !networkingAvailable)
      "features.network.doh.enable is set, but networking options are unavailable in this evaluation.";
in {
  config = mkMerge [
    (mkIf (dohEnabled && dnscryptAvailable) {
      services.dnscrypt-proxy2 = {
        enable = true;
        settings = {
          listen_addresses = [
            "127.0.0.1:53"
            "[::1]:53"
          ];
          ipv6_servers = false;
          require_dnssec = true;
          cache = true;
          sources.public-resolvers = {
            urls = [
              "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
              "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
            ];
            cache_file = "/var/cache/dnscrypt-proxy/public-resolvers.md";
            minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
          };
          server_names = [
            "serbica"
            "cs-nl"
            "comss.one"
            "doh-ibksturm"
            "ibksturm"
            "cloudflare"
            "cloudflare-security"
            "adguard-dns-doh"
            "mullvad-adblock-doh"
            "mullvad-doh"
            "nextdns"
            "quad9-dnscrypt-ip4-filter-pri"
            "google"
          ];
        };
      };
    })
    (mkIf (dohEnabled && networkingAvailable) {
      networking = {
        nameservers = [
          "127.0.0.1"
          "::1"
        ];
        dhcpcd = {
          enable = false;
          extraConfig = "nohook resolv.conf";
        };
        wireless.iwd.settings.Network.NameResolvingService = "none";
      };
    })
    (optionalAttrs (warningMessages != []) {warnings = warningMessages;})
  ];
}
