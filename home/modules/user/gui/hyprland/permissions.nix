{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
with lib; let
  hy3Enabled = config.features.gui.hy3.enable or false;
  hy3PluginPath = "${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so";
  hy3Permission =
    if hy3Enabled
    then ''
        permission = ${hy3PluginPath}, plugin, allow
    ''
    else "";
in
  mkIf config.features.gui.enable (lib.mkMerge [
    (xdg.mkXdgText "hypr/permissions.conf" ''
        ecosystem {
          enforce_permissions = 1
        }
        permission = ${lib.getExe pkgs.grim}, screencopy, allow
        permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
      ${hy3Permission}
      '')
    # Ensure the generated file replaces any pre-existing file
    {xdg.configFile."hypr/permissions.conf".force = true;}
  ])
