{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
with lib;
  mkIf config.features.gui.enable (lib.mkMerge [
    (
      let
        hyprsplitEnabled = config.features.gui.hyprsplit.enable or false;
        hy3PluginPath = "${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so";
        hyprsplitPluginPath = "${pkgs.hyprlandPlugins.hyprsplit}/lib/libhyprsplit.so";
        hy3Perms = ''
          permission = ${hy3PluginPath}, plugin, allow
        '';
        hyprsplitPerms =
          if hyprsplitEnabled
          then ''
            permission = ${hyprsplitPluginPath}, plugin, allow
          ''
          else "";
      in
        xdg.mkXdgText "hypr/permissions.conf" (''
            ecosystem {
              enforce_permissions = 1
            }
            permission = ${lib.getExe pkgs.grim}, screencopy, allow
            permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
          ''
          + hy3Perms
          + hyprsplitPerms
          )
    )
    # Ensure the generated file replaces any pre-existing file
    {xdg.configFile."hypr/permissions.conf".force = true;}
  ])
