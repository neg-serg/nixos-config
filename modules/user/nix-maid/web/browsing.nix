{
  lib,
  neg,
  impurity ? null,
  ...
}:
with lib;
let
  n = neg impurity;
in
{
  imports = [
    ./defaults.nix
    ./librewolf.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (n.mkHomeFiles {
      ".config/surfingkeys.js".source = n.linkImpure ../../../../files/surfingkeys.js;
    })
  ];
}
