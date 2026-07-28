{
  pkgs,
  lib,
  ...
}:
let
  # Replicating logic from modules/dev/python/pkgs.nix
  myPythonPackages =
    ps: with ps; [
      # Core
      annoy
      beautifulsoup4
      colored
      docopt
      fonttools
      mutagen
      numpy
      orjson
      pillow
      psutil
      requests
      tabulate
      # Tools
      dbus-python
      fontforge

      pynvim
    ];
  pythonEnv = pkgs.python3-lto.withPackages myPythonPackages;
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
