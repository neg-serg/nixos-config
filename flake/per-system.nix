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
  mkCustomPkgs = flakeLib.mkCustomPkgs; # pkgs is now passed from flake.nix
  nixfmtPkg = nixpkgs.legacyPackages.${system}.nixfmt;
in
{
  packages = (mkCustomPkgs pkgs) // {
    default = pkgs.zsh; # default shell for flake environment
    # The headless compositor the developer harnesses run scenes in. The scripts
    # find it as `nix build <repo>#pleamar-wm` (`resolve_pleamar_tool`), which is
    # why it is exported rather than only installed.
    pleamar-wm = inputs.pleamar-wm.packages.${system}.pleamar-wm;
  };

  formatter = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = [
      nixfmtPkg # nix formatter
      pkgs.black # python formatter
      # markdown formatter — with the mdformat-gfm plugin so GFM tables are
      # preserved; core mdformat collapses table rows into one paragraph
      (pkgs.python3.withPackages (ps: [
        ps.mdformat
        ps.mdformat-gfm
      ]))
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
}
