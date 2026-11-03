{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.web.chat or { };
  proxyEnabled = config.lib.neg.enabled "net.proxy";

  # On-demand launchers: the Telegram closure stays out of the system closure.
  # The first run builds the matching flake package and registers a GC root in
  # $HOME; later runs exec the binary directly. The wrapper itself references
  # only nix, never Telegram, so system-path stays small.
  mkTelegramLauncher =
    { name, attr }:
    pkgs.writeShellScriptBin name ''
      root="$HOME/.local/state/nix-apps/${name}"
      if [ ! -e "$root" ]; then
        mkdir -p "$(dirname "$root")"
        rm -f "$root"
        out=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths "git+file:///etc/nixos#${attr}")
        ${pkgs.nix}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
      fi
      exec "$root/bin/${name}" "$@"
    '';

  telegram = mkTelegramLauncher {
    name = "telegram-desktop";
    attr = "telegram-desktop";
  };
  telegramProxy = mkTelegramLauncher {
    name = "telegram-desktop-proxy";
    attr = "telegram-desktop-proxy";
  };
in
lib.mkIf (cfg.enable or true) {
  environment.systemPackages = [
    pkgs.tdl # Telegram CLI downloader/uploader

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
