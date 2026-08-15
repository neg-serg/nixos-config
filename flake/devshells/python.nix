{
  pkgs,
  ...
}:
let
  # Shared package list — single source in lib/python-packages.nix
  pythonLists = import ../../lib/python-packages.nix { };
  pythonEnv = pkgs.python3-lto.withPackages pythonLists.myPythonPackages;
in
pkgs.mkShell {
  nativeBuildInputs = [
    pythonEnv
    pkgs.pipx # Install and run Python applications in isolated environments
    pkgs.black # Python code formatter
    pkgs.ruff # Extremely fast Python linter and code formatter
    pkgs.mypy # Optional static typing for Python
  ];
}
