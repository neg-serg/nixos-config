{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.web.chat or { };
  proxyEnabled = config.features.net.proxy.enable or false;
in
lib.mkIf (cfg.enable or true) {
  environment.systemPackages = [
    pkgs.tdl # Telegram CLI downloader/uploader
  ]
  ++ lib.optionals proxyEnabled [
    pkgs.proxychains # Force any app through SOCKS5 proxy via LD_PRELOAD

    (pkgs.writeShellScriptBin "telegram-desktop-proxy" ''
      exec ${pkgs.proxychains}/bin/proxychains4 -q \
        flatpak run org.telegram.desktop "$@"
    '')

    (pkgs.makeDesktopItem {
      name = "telegram-desktop-proxy";
      desktopName = "Telegram (via proxy)";
      exec = "telegram-desktop-proxy";
      icon = "telegram";
      categories = [
        "Network"
        "InstantMessaging"
      ];
    })
  ];

  environment.sessionVariables = lib.mkIf proxyEnabled {
    ALL_PROXY = "socks5://127.0.0.1:10808";
  };
}
