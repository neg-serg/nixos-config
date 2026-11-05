{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.web.chat or { };
  proxyEnabled = config.lib.neg.enabled "net.proxy";

  # On-demand launchers: the Telegram and tdl closures stay out of the system
  # closure. The first run builds the matching flake package and registers a GC
  # root in $HOME; later runs exec the binary directly. The wrapper itself
  # references only nix, so system-path stays small.
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };

  telegram = onDemand {
    name = "telegram-desktop";
    attr = "telegram-desktop";
    binary = "Telegram";
  };
  telegramProxy = onDemand {
    name = "telegram-desktop-proxy";
    attr = "telegram-desktop-proxy";
  };
in
lib.mkIf (cfg.enable or true) {
  environment.systemPackages = [
    # Telegram CLI downloader/uploader, built on first call like the GUI.
    (onDemand {
      name = "tdl";
      attr = "tdl";
    })

    telegram
    (pkgs.makeDesktopItem {
      name = "org.telegram.desktop";
      desktopName = "Telegram";
      exec = "telegram-desktop";
      icon = "telegram";
      categories = [
        "Network"
        "InstantMessaging"
      ];
    })
  ]
  ++ lib.optionals proxyEnabled [
    pkgs.proxychains # Force any app through SOCKS5 proxy via LD_PRELOAD

    telegramProxy
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
}
