{lib, config, pkgs, ...}: let
  devEnabled = config.features.dev.enable or false;
  pyCfg = config.features.dev.python or {};
  boolFlag = name: lib.attrByPath [name] true pyCfg;
  groups = {
    core = ps:
      with ps; [
        colored
        docopt
        beautifulsoup4
        numpy
        annoy
        orjson
        mutagen
        pillow
        psutil
        requests
        tabulate
        fonttools
      ];
    tools = ps:
      with ps; [
        dbus-python
        fontforge
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
    pkgs.pipx
    pythonEnv
  ];
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
