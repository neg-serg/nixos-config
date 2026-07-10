{
  lib,
  neg,
  ...
}:
let
  n = neg;

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
      hyprlandLuaText,
    }:
    n.mkHomeFiles (
      {
        ".config/hypr/hyprland.conf".text = hyprlandConfText;

        ".config/hypr/hyprland.lua".text = hyprlandLuaText;

        ".config/hypr/hyprlock.conf".text = ''
          # Hyprlock Configuration
          source = ~/.config/hypr/hyprlock/theme.conf
        '';

        # Hyprscratch config: Telegram scratchpad (name without dots — togglespecialworkspace ломается на '.')
        ".config/hypr/hyprscratch.conf".text = ''
          telegram {
              class = org.telegram.desktop
              command = Telegram
              options = special
          }
        '';

        # Ensure local.d directory exists with at least one .conf file so the glob never fails
        ".config/hypr/local.d/00-override.conf".text =
          "# Local Hyprland overrides (Lua API)\n# Use hl.env(), hl.config(), hl.bind(), hl.window_rule() etc.\n# See ~/.config/hypr/hyprland.lua for reference\n";
      }
      // (mkFiles ".config/hypr/animations" animDir (builtins.attrNames (builtins.readDir animDir)))
      // (mkFiles ".config/hypr/hyprlock" lockDir (builtins.attrNames (builtins.readDir lockDir)))
    );
}
