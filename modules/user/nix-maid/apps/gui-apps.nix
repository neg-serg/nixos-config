{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  n = neg;
in
{
  config = lib.mkMerge [
    {
      # Packages
      environment.systemPackages = [
      ];
    }
    (n.mkHomeFiles {
      # Handlr Config
      ".config/handlr/handlr.toml".text = ''
        enable_selector = false
        selector = "vicinae dmenu -p 'Open With: ❯>'"
      '';
    })
  ];
}
