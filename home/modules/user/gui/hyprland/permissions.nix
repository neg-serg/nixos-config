{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
with lib;
  mkIf config.features.gui.enable (lib.mkMerge [
    (xdg.mkXdgText "hypr/permissions.conf" ''
        ecosystem {
          enforce_permissions = 1
        }
        permission = ${lib.getExe pkgs.grim}, screencopy, allow
        permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
      '')
    # Ensure the generated file replaces any pre-existing file
    {xdg.configFile."hypr/permissions.conf".force = true;}
  ])
