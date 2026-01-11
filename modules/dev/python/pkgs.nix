{
  lib,
  config,
  pkgs,
  ...
}:
let
  devEnabled = config.features.dev.enable or false;
  pyCfg = config.features.dev.python or { };
  boolFlag = name: lib.attrByPath [ name ] true pyCfg;
  groups = {
    core =
      ps: with ps; [
        annoy # approximate nearest neighbors library
        beautifulsoup4 # library for pulling data out of HTML and XML files
        colored # simple library for color and formatting in terminal
        docopt # Pythonic command line arguments parser
        fonttools # library for manipulating fonts
        mutagen # read and write audio metadata
        numpy # fundamental package for scientific computing
        orjson # fast, correct JSON library
        pillow # friendly fork of PIL (Python Imaging Library)
        psutil # process and system monitoring library
        requests # elegant and simple HTTP library
        tabulate # pretty-print tabular data
      ];
    tools =
      ps: with ps; [
        dbus-python # Python bindings for libdbus
        fontforge # outline font editor
        neopyter # bridge between Neovim and Jupyter
        pynvim # Python client for Neovim
      ];
  };
  mkPythonPackages =
    ps: lib.concatLists (lib.mapAttrsToList (name: fn: if boolFlag name then fn ps else [ ]) groups);
  pythonEnv = pkgs.python3-lto.withPackages mkPythonPackages;
  packages = [
    pkgs.pipx # isolate Python CLI apps outside nix shell envs
    pythonEnv # composable python3-lto env w/ requested libs
  ];
in
{
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
