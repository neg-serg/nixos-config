{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.features.dev.python;

  # Python with LTO optimizations (defined in overlay) and common packages
  # used by repository scripts and local tools.
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
    ];

  pythonEnv = (pkgs.python3-lto or pkgs.python3).withPackages myPythonPackages;
in
{
  config = lib.mkIf (cfg.core or true) {
    environment.systemPackages = [
      pythonEnv
    ]
    ++ lib.optionals (cfg.tools or false) [ pkgs.python3Packages.python-lsp-server ];
  };
}
