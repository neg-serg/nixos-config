{
  lib,
  neg,
  ...
}:
with lib;
let
  n = neg;
in
{
  imports = [
    ./defaults.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (n.mkHomeFiles {
      ".config/surfingkeys.js".source = ../../../../files/surfingkeys.js;
    })
  ];
}
