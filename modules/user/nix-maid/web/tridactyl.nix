{
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
lib.mkIf config.features.web.enable (
  n.mkHomeFiles (
    let
      # Use relative path to home/files for stability
      base = ../../../../files/misc/tridactyl;
      rcPath = "${base}/tridactylrc";
      themesPath = base + "/themes";
      mozillaPath = base + "/mozilla";
      userjsPath = base + "/user.js";
    in
    {
      ".config/tridactyl/tridactylrc".text = ''
        source ${rcPath}
      '';

      ".config/tridactyl/user.js".source = userjsPath;

      ".config/tridactyl/themes" = {
        source = themesPath;
      };

      ".config/tridactyl/mozilla" = {
        source = mozillaPath;
      };
    }
  )
)
