{
  lib,
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
      ".config/surfingkeys.js".source = ../../../../files/surfingkeys.js;
      # Vivaldi CSS mod: compact address bar (loaded from the profile css-mods dir)
      ".config/vivaldi/Default/vivaldi-data/css-mods/css/compact-addressbar.css".source =
        ../../../../files/vivaldi/compact-addressbar.css;
    })
  ];
}
