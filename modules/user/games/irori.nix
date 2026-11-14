##
# Module: user/games/irori
# Purpose: Irori — game launcher for Epic Games, GOG, Amazon Games, ZOOM Platform,
# itch.io and Steam (packages/irori), with its Steam library, Wine/Proton
# downloads and emulator pages.
#
# The package carries a WebKitGTK sign-in window, so the system installs the
# on-demand launcher (lib/on-demand-app.nix) and a desktop entry only: the
# app's closure is built on first launch and pinned under
# ~/.local/state/nix-apps/irori, refreshed with `nix-apps update irori`.
#
# The desktop entry names the icon under $HOME for the same reason a store path
# would drag the whole closure into system-path.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.games or { };

  onDemand = config.lib.neg.onDemand pkgs;

  # Where the on-demand launcher pins its GC root on first run.
  appRoot = "${config.lib.neg.homeDir}/.local/state/nix-apps";
in
{
  config = lib.mkIf (cfg.enable && config.lib.neg.enabled "games.irori") {
    environment.systemPackages = lib.mkAfter [
      (onDemand {
        name = "irori";
        attr = "irori";
      })

      (pkgs.makeDesktopItem {
        name = "irori";
        desktopName = "Irori";
        genericName = "Game Launcher";
        comment = "Play your Epic, GOG, Amazon, itch.io and Steam games from one library";
        exec = "irori %u";
        icon = "${appRoot}/irori/share/icons/hicolor/scalable/apps/irori.svg";
        categories = [ "Game" ];
        keywords = [
          "epic"
          "gog"
          "amazon"
          "itch"
          "steam"
          "launcher"
          "proton"
        ];
        startupWMClass = "irori";
        # Heroic's heroic:// links are understood too, but the entry only claims
        # Irori's own scheme; the association lives in gui/xdg.nix.
        mimeTypes = [ "x-scheme-handler/irori" ];
        actions = {
          big-picture = {
            name = "Big Picture";
            exec = "irori --big-picture";
          };
        };
      })
    ];
  };
}
