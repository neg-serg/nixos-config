{
  lib,
  config,
  neg,
  ...
}:
with lib;
{
  imports = [
    ./defaults.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (neg.mkHomeFiles {
      ".config/surfingkeys.js".source = config.lib.neg.path "files/surfingkeys.js";
      # Vivaldi CSS mod: compact address bar (dir is set via css_ui_mods_directory pref)
      ".config/vivaldi/css-mods/compact-addressbar.css".source =
        config.lib.neg.path "files/vivaldi/compact-addressbar.css";
    })
  ];
}
