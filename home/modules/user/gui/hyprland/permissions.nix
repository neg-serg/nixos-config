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
        hy3Perms = ''
          # Allow loading hy3 plugin. Use a regex to survive path hash/version changes
          # and possible library filename variants (e.g., libhyprland-hy3.so).
          # RE2 full-match is used; keep anchors.
          permission = ^/nix/store/[^/]+-hy3-[^/]+/lib/[^/]*hy3[^/]*\.so$, plugin, allow
          permission = /etc/hypr/libhy3.so, plugin, allow
        '';
        hyprsplitPerms =
          if (config.features.gui.hyprsplit.enable or false)
          then ''
            # Allow loading hyprsplit plugin
            permission = ^/nix/store/[^/]+-hyprsplit-[^/]+/lib/[^/]*hyprsplit[^/]*\.so$, plugin, allow
          ''
          else "";
        hyprVrrPerms =
          if (config.features.gui.vrr.enable or false)
          then ''
            # Allow loading hyprland-vrr plugin
            permission = ^/nix/store/[^/]+-hyprland-vrr-[^/]+/lib/[^/]*hyprland-vrr[^/]*\.so$, plugin, allow
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
          + hyprVrrPerms)
    )
    # Ensure the generated file replaces any pre-existing file
    {xdg.configFile."hypr/permissions.conf".force = true;}
  ])
