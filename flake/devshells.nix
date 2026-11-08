{
  nixpkgs,
  pkgs,
  inputs,
  ...
}:
_system:
let
  inherit (nixpkgs) lib;
in
{
  devShells = import ./devshells/default.nix {
    inherit pkgs lib;
    inherit (inputs) import-tree;
    mkShell = pkgs.mkShell;
  };
}
