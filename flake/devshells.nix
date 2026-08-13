{
  nixpkgs,
  pkgs,
  ...
}:
system:
let
  inherit (nixpkgs) lib;
  nixfmtPkg = nixpkgs.legacyPackages.${system}.nixfmt;
in
{
  devShells = import ./devshells/default.nix {
    inherit
      pkgs
      lib
      nixfmtPkg
      ;
  };
}
