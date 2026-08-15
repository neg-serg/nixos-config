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
      # Vivaldi CSS mod: hide tab bar + window control buttons (single-bar layout)
      ".config/vivaldi/css-mods/minimal-ui.css".source =
        config.lib.neg.path "files/vivaldi/minimal-ui.css";
    })
  ];
}
