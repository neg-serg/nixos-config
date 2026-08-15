{
  nixpkgs,
  pkgs,
  ...
}:
_system:
let
  inherit (nixpkgs) lib;
in
{
  devShells = import ./devshells/default.nix {
    inherit
      pkgs
      lib
      ;
  };
}
