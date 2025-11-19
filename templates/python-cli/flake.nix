{
  description = "Minimal Python CLI with devShell (ruff/black/pytest)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = {nixpkgs}: let
    inherit (nixpkgs) lib;
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f: lib.genAttrs systems (system: f (import nixpkgs {inherit system;}));
  in {
    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        name = "python-cli-dev";
        packages = [
          pkgs.python312
          pkgs.python312Packages.pip
          pkgs.python312Packages.setuptools
          pkgs.python312Packages.wheel
          pkgs.ruff
          pkgs.black
          pkgs.pytest
        ];
      };
    });
  };
}
