{
  self,
  inputs,
  nixpkgs,
  flakeLib,
  ...
}: system: let
  inherit (nixpkgs) lib;
  pkgs = flakeLib.mkPkgs system;
  mkCustomPkgs = flakeLib.mkCustomPkgs;

  # Pre-commit utility per system
  preCommit = inputs.pre-commit-hooks.lib.${system}.run {
    src = self;
    hooks = {
      alejandra.enable = true;
      statix.enable = true;
      deadnix.enable = true;
    };
  };
in {
  packages =
    (mkCustomPkgs pkgs)
    // {
      default = pkgs.zsh;
      docs-modules = import ./docs-modules.nix {
        inherit pkgs lib self;
      };
    };

  formatter = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = with pkgs; [
      alejandra
      black
      python3Packages.mdformat
      shfmt
      treefmt
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

  checks = {
    fmt-treefmt =
      pkgs.runCommand "fmt-treefmt" {
        nativeBuildInputs = with pkgs; [
          alejandra
          black
          python3Packages.mdformat
          shfmt
          treefmt
          findutils
        ];
        src = ../.;
      } ''
        set -euo pipefail
        cp -r "$src" ./src
        chmod -R u+w ./src
        cd ./src
        export XDG_CACHE_HOME="$PWD/.cache"
        mkdir -p "$XDG_CACHE_HOME"
        cp ${../treefmt.toml} ./.treefmt.toml
        treefmt --config-file ./.treefmt.toml --tree-root . --fail-on-change .
        touch "$out"
      '';
    lint-deadnix = pkgs.runCommand "lint-deadnix" {nativeBuildInputs = with pkgs; [deadnix];} ''
      cd ${self}
      deadnix --fail --exclude home .
      touch "$out"
    '';
    lint-statix = pkgs.runCommand "lint-statix" {nativeBuildInputs = with pkgs; [statix];} ''cd ${self}; statix check .; touch "$out"'';
    pre-commit = preCommit;
    lint-md-lang = pkgs.runCommand "lint-md-lang" {nativeBuildInputs = with pkgs; [bash coreutils findutils gnugrep gitMinimal];} ''
      set -euo pipefail
      cd ${self}
      bash scripts/check-markdown-language.sh
      : > "$out"
    '';
    tests-caddy = pkgs.testers.runNixOSTest (import ../tests/caddy.nix);
  };

  devShells = {
    default = pkgs.mkShell {
      inherit (preCommit) shellHook;
      packages = with pkgs; [alejandra deadnix statix nil just jq];
    };
  };

  apps = let
    genOptions = pkgs.writeShellApplication {
      name = "gen-options";
      runtimeInputs = with pkgs; [git jq nix];
      text = ''
        set -euo pipefail
        exec "${self}/scripts/gen-options.sh" "$@"
      '';
    };
    fmtApp = pkgs.writeShellApplication {
      name = "fmt";
      runtimeInputs = with pkgs; [
        alejandra
        black
        python3Packages.mdformat
        shfmt
        treefmt
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
  in {
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
