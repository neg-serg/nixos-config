# Shared Python package list — single source of truth for the system python
# env (modules/dev/python/pkgs.nix) and the python devshell
# (flake/devshells/python.nix). Add/remove packages HERE, not in both files.
{ }:
{
  # ps: -> [ ... ] — package list for python3.withPackages
  myPythonPackages =
    ps: with ps; [
      # Base utilities
      colored
      docopt
      numpy
      pillow
      psutil
      requests
      tabulate

      # Data and parsing
      beautifulsoup4
      orjson

      # Tool integration
      dbus-python
      pynvim

      # Media/Type related (used by local-bin)
      fontforge
      fonttools
      mutagen

      # ML / misc (devshell and scripts)
      annoy
    ];
}
