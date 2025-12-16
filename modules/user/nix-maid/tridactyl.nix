{
  lib,
  config,
  ...
}:
lib.mkIf config.features.web.enable {
  users.users.neg.maid = let
    # Use relative path to home/files for stability and to avoid dependency on undefined vars
    base = ../../../files/misc/tridactyl;
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
    file.home.".config/tridactyl/tridactylrc".text = rcText;

    # Link supplemental files/dirs from misc assets tracked in the repo
    file.home.".config/tridactyl/user.js".source = userjsPath;

    file.home.".config/tridactyl/themes" = {
      source = themesPath;
    };

    file.home.".config/tridactyl/mozilla" = {
      source = mozillaPath;
    };
  };
}
