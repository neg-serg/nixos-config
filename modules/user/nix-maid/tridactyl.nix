{
  lib,
  config,
  xdg,
  negLib,
  ...
}:
with lib;
  mkIf config.features.web.enable (
    let
      base = "${config.neg.hmConfigRoot}/files/misc/tridactyl";
      rcPath = base + "/tridactylrc";
      themesPath = base + "/themes";
      mozillaPath = base + "/mozilla";
      userjsPath = base + "/user.js";
      # Compose Tridactyl config: only source user's rc; avoid overriding keys here
      rcText = ''
        source ${rcPath}
      '';
    in
      lib.mkMerge [
        # Ensure ~/.config/tridactyl is a real dir (not a previous symlink)
        {home.activation.fixTridactylDir = negLib.mkEnsureRealDir "${config.xdg.configHome}/tridactyl";}
        # Write rc overlay that sources user's file and then applies small fixups
        (xdg.mkXdgText "tridactyl/tridactylrc" rcText)
        # Link supplemental files/dirs from misc assets tracked in the repo
        (xdg.mkXdgSource "tridactyl/user.js" {
          source = userjsPath;
          recursive = false;
        })
        (xdg.mkXdgSource "tridactyl/themes" {
          source = themesPath;
          recursive = true;
        })
        (xdg.mkXdgSource "tridactyl/mozilla" {
          source = mozillaPath;
          recursive = true;
        })
      ]
  )
