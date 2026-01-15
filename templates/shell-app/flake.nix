{
  description = "Shell app packaged with writeShellApplication";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.writeShellApplication {
          name = "mytool";
          runtimeInputs = [ ];
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail
            echo "Hello from mytool"
          '';
        };
      });
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "shell-app-dev";
          packages = [
            pkgs.shellcheck # Shell script analysis tool
            pkgs.shfmt # Shell parser and formatter
          ];
        };
      });
    };
}
