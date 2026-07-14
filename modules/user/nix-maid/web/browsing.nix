{
  lib,
  neg,
  ...
}:
with lib;
let
in
{
  imports = [
    ./defaults.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (neg.mkHomeFiles {
      ".config/surfingkeys.js".source = ../../../../files/surfingkeys.js;
    })
  ];
}
