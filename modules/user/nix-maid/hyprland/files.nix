{
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;

  hyprConfDir = ../../../../files/gui/hypr;
  animDir = ../../../../files/gui/hypr/animations;
  lockDir = ../../../../files/gui/hypr/hyprlock;

  mkFiles =
    destDir: sourceDir: files:
    files
    |> map (f: {
      name = "${destDir}/${f}";
      value = {
        source = sourceDir + "/${f}";
      };
    })
    |> builtins.listToAttrs;
in
{
  generateFileLinks =
    {
      hyprlandConfText,
      permissionsConfText,
      hyprlandLuaText,
    }:
    n.mkHomeFiles (
      {
        ".config/hypr/hyprland.conf".text = hyprlandConfText;
        ".config/hypr/permissions.conf".text = permissionsConfText;

        ".config/hypr/hyprland.lua".text = hyprlandLuaText;
        ".config/hypr/xdph.conf".text = ''
          screencopy {
              max_fps = 60
          }
        '';

        ".config/hypr/hyprlock.conf".text = ''
          # Hyprlock Configuration
          source = ~/.config/hypr/hyprlock/theme.conf
        '';

        # Wallust generates this file at runtime; provide a fallback with known-good defaults so hyprlock never fails on source
        ".cache/wallust/hyprland.conf".text = ''
          $col_border_active_base = rgba(00285981)
          $col_border_inactive   = rgba(00000000)
          $shadow_color          = rgba(005fafaa)
        '';

        # Ensure local.d directory exists with at least one .conf file so the glob never fails
        ".config/hypr/local.d/00-override.conf".text = "# Local Hyprland overrides (Lua API)\n# Use hl.env(), hl.config(), hl.bind(), hl.window_rule() etc.\n# See ~/.config/hypr/hyprland.lua for reference\n";
      }
      // (mkFiles ".config/hypr/animations" animDir (builtins.attrNames (builtins.readDir animDir)))
      // (mkFiles ".config/hypr/hyprlock" lockDir (builtins.attrNames (builtins.readDir lockDir)))
    );
}
