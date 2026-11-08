##
# Module: fun/launchers-packages
# Purpose: Ship Proton/Wine helper utilities system-wide for game launchers.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = (config.lib.neg.enabled "fun") && (config.lib.neg.enabled "gui");
  onDemand = config.lib.neg.onDemand pkgs;
  packages = [
    (onDemand {
      name = "protontricks";
      attr = "protontricks";
      aliases = [ "protontricks-launch" ];
    }) # Winetricks wrapper for Proton, built on first use
    pkgs.protonup-ng # install/update Proton-GE builds
    pkgs.vkbasalt # Vulkan post-processing layer
    pkgs.vkbasalt-cli # CLI for vkBasalt configuration
  ];
  # The package's own desktop entries live inside the on-demand root, which is
  # not on XDG_DATA_DIRS; the menu entries are recreated here instead. The
  # `wine` icon comes from the icon theme, so the launcher still shows it.
  desktopItems = [
    (pkgs.makeDesktopItem {
      name = "protontricks";
      desktopName = "Protontricks";
      comment = "A simple wrapper that does winetricks things for Proton enabled games";
      exec = "protontricks --no-term --gui";
      icon = "wine";
      categories = [ "Utility" ];
    })
    (pkgs.makeDesktopItem {
      name = "protontricks-launch";
      desktopName = "Protontricks Launcher";
      comment = "Run a Windows executable inside a Proton game's Wine prefix";
      exec = "protontricks-launch --no-term %f";
      icon = "wine";
      categories = [ "Utility" ];
    })
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter (packages ++ desktopItems);
  };
}
