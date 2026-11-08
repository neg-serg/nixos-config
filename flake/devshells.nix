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
    # Every shell enables the repo hooks once, so a clone that never ran
    # `just hooks-enable` still gets the lint/commit-msg gate. The check is
    # scoped to this repo (Justfile + .githooks in the git root).
    mkShell =
      args:
      pkgs.mkShell (
        args
        // {
          shellHook = ''
            ${args.shellHook or ""}
            if command -v git > /dev/null 2>&1; then
              root=$(git rev-parse --show-toplevel 2> /dev/null || true)
              if [ -n "$root" ] && [ -f "$root/Justfile" ] && [ -d "$root/.githooks" ] \
                && [ -z "$(git -C "$root" config --get core.hooksPath 2> /dev/null)" ]; then
                git -C "$root" config core.hooksPath .githooks
                echo "neg: git hooks enabled (core.hooksPath=.githooks)"
              fi
            fi
          '';
        }
      );
  };
}
