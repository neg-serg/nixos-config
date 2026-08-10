{
  self,
  inputs,
  nixpkgs,
  flakeLib,
  mkTestHost,
  pkgs,
  ...
}:
system:
let
  inherit (nixpkgs) lib;
  mkCustomPkgs = flakeLib.mkCustomPkgs; # pkgs is now passed from flake.nix
  nixfmtPkg = nixpkgs.legacyPackages.${system}.nixfmt;
in
{
  packages = (mkCustomPkgs pkgs) // {
    default = pkgs.zsh; # default shell for flake environment
    docs-modules = import ./docs-modules.nix {
      inherit pkgs lib self;
    };
  };

  formatter = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = [
      nixfmtPkg # nix formatter
      pkgs.black # python formatter
      pkgs.python3Packages.mdformat # markdown formatter
      pkgs.shfmt # shell script formatter
      pkgs.treefmt # unified formatting tool
    ];
    text = ''
      set -euo pipefail
      if git rev-parse --show-toplevel >/dev/null 2>&1; then
        repo_root="$(git rev-parse --show-toplevel)"
      else
        repo_root="${self}"
      fi
      cd "$repo_root"
      tmp_conf=$(mktemp)
      trap 'rm -f "$tmp_conf"' EXIT
      cp ${../treefmt.toml} "$tmp_conf"
      exec treefmt --config-file "$tmp_conf" --tree-root "$repo_root" "$@"
    '';
  };

  checks = import ./checks.nix {
    inherit
      nixpkgs
      self
      inputs
      mkTestHost
      ;
  } pkgs;
}
