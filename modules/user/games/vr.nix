# VR Gaming Module
#
# SteamVR, DeoVR and other VR-related launchers.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.games or { };

  # Import consolidated game scripts for SteamVR launcher
  gameScripts = import ../../../packages/game-scripts {
    inherit pkgs lib config;
  };

  # DeoVR Steam launcher
  deovrSteamCli = pkgs.writeShellApplication {
    name = "deovr";
    text = ''
      exec steam steam://rungameid/837380 "$@"
    '';
  };

  deovrSteamDesktop = pkgs.makeDesktopItem {
    name = "deovr";
    desktopName = "DeoVR Video Player (Steam)";
    comment = "Launch DeoVR via Steam (AppID 837380)";
    exec = "steam steam://rungameid/837380";
    terminal = false;
    categories = [
      "Game"
      "AudioVideo"
    ];
  };

  steamvrDesktop = pkgs.makeDesktopItem {
    name = "steamvr-hypr";
    desktopName = "SteamVR (Hyprland)";
    comment = "Launch SteamVR under Hyprland";
    exec = "steamvr";
    terminal = false;
    categories = [
      "Game"
      "Utility"
    ];
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      gameScripts.steamvr
      steamvrDesktop
      deovrSteamCli
      deovrSteamDesktop
    ];
  };
}
