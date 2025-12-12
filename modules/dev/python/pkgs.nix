{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  pyCfg = config.features.dev.python or {};
  boolFlag = name: lib.attrByPath [name] true pyCfg;
  groups = {
    core = ps:
      with ps; [
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
      ];
    tools = ps:
      with ps; [
        dbus-python
        fontforge
        neopyter
        pynvim
      ];
  };
  mkPythonPackages = ps:
    lib.concatLists (
      lib.mapAttrsToList (
        name: fn:
          if boolFlag name
          then fn ps
          else []
      )
      groups
    );
  pythonEnv = pkgs.python3-lto.withPackages mkPythonPackages;
  packages = [
    pkgs.pipx # isolate Python CLI apps outside nix shell envs
    pythonEnv # composable python3-lto env w/ requested libs
  ];
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
