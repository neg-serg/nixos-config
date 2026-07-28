{
  self,
  inputs,
  nixpkgs,
  flakeLib,
  pkgs,
  ...
}:
system:
let
  inherit (nixpkgs) lib;
  nixfmtPkg = nixpkgs.legacyPackages.${system}.nixfmt;

  # Pre-commit utility per system
  preCommit = inputs.pre-commit-hooks.lib.${system}.run {
    src = self;
    hooks = {
      nixfmt-rfc-style = {
        enable = true;
        package = nixfmtPkg;
        excludes = [ "flake.nix" ];
      };
      statix.enable = true;
      deadnix.enable = true;
    };
  };
in
{
  devShells = import ./devshells/default.nix {
    inherit pkgs lib preCommit nixfmtPkg;
  };
}
