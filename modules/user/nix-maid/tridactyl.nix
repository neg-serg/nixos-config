{
  lib,
  config,
  ...
}:
lib.mkIf config.features.web.enable {
  users.users.neg.maid = let
    # Use relative path to home/files for stability and to avoid dependency on undefined vars
    base = ../../../home/files/misc/tridactyl;
    rcPath = "${base}/tridactylrc";
    themesPath = base + "/themes";
    mozillaPath = base + "/mozilla";
    userjsPath = base + "/user.js";
    # Compose Tridactyl config: only source user's rc; avoid overriding keys here
    rcText = ''
      source ${rcPath}
    '';
  in {
    # Write rc overlay that sources user's file and then applies small fixups
    file.xdg_config."tridactyl/tridactylrc".text = rcText;

    # Link supplemental files/dirs from misc assets tracked in the repo
    file.xdg_config."tridactyl/user.js".source = userjsPath;

    file.xdg_config."tridactyl/themes" = {
      source = themesPath;
    };

    file.xdg_config."tridactyl/mozilla" = {
      source = mozillaPath;
    };
  };
}
