{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.features.dev.python;

  # Shared package list — single source in lib/python-packages.nix
  pythonLists = import ../../../../lib/python-packages.nix { };
  myPythonPackages = pythonLists.myPythonPackages;

  pythonEnv = (pkgs.python3-lto or pkgs.python3).withPackages myPythonPackages; # High-level dynamically-typed programming language
in
{
  config = lib.mkIf (cfg.core or true) {
    environment.systemPackages = [
      pythonEnv
    ]
    ++ lib.optionals (cfg.tools or false) [ pkgs.python3Packages.python-lsp-server ];
  };
}
