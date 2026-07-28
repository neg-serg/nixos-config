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

  genOptions = pkgs.writeShellApplication {
    name = "gen-options";
    runtimeInputs = [
      pkgs.git # version control
      pkgs.jq # json processor
      pkgs.nix # nix package manager
    ];
    text = ''
      set -euo pipefail
      exec "${self}/scripts/dev/gen-options.sh" "$@"
    '';
  };

  fmtApp = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = [
      nixfmtPkg
      pkgs.black # Python code formatter
      pkgs.python3Packages.mdformat
      pkgs.shfmt # Shell parser and formatter
      pkgs.treefmt # One CLI to format the code tree
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
in
{
  apps = {
    gen-options = {
      type = "app";
      program = "${genOptions}/bin/gen-options";
    };
    fmt = {
      type = "app";
      program = "${fmtApp}/bin/fmt";
    };
  };
}
