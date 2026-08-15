{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.web.chat or { };
  proxyEnabled = config.lib.neg.enabled "net.proxy";
in
lib.mkIf (cfg.enable or true) {
  environment.systemPackages = [
    pkgs.telegram-desktop # Telegram Desktop (nixpkgs build, proper glibc integration)
    pkgs.tdl # Telegram CLI downloader/uploader
  ]
  ++ lib.optionals proxyEnabled [
    pkgs.proxychains # Force any app through SOCKS5 proxy via LD_PRELOAD

    (pkgs.writeShellScriptBin "telegram-desktop-proxy" ''
      exec ${pkgs.proxychains}/bin/proxychains4 -q \
        ${lib.getExe pkgs.telegram-desktop} "$@"
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
}
