{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.features.dev.python;

  # Shared package list — single source in lib/python-packages.nix
  pythonLists = import (config.lib.neg.path "lib/python-packages.nix") { };
  myPythonPackages = pythonLists.myPythonPackages;

  # priority 0 (lower = wins) so the FULL env beats the nvim debugpy-only env
  # (modules/user/neovim.nix sets priority 1) and any other stray python3
  # providers — otherwise system python3 is just debugpy and numpy/cv2 etc.
  # are not importable even though they are in the list.
  pythonEnv = ((pkgs.python3-lto or pkgs.python3).withPackages myPythonPackages).overrideAttrs (o: {
    meta = (o.meta or { }) // {
      priority = 0;
    };
  }); # High-level dynamically-typed programming language
in
{
  config = lib.mkIf (cfg.core or true) {
    environment.systemPackages = [
      pythonEnv
    ]
    ++ lib.optionals (cfg.tools or false) [ pkgs.python3Packages.python-lsp-server ];
    # Neovim's Python provider (programs.neovim.withPython3) ships pynvim only, so
    # remote plugins needing more (molten-nvim → jupyter_client) point Neovim at
    # this env instead: lua/plugins/integration/molten-nvim.lua reads the variable.
    environment.sessionVariables.NVIM_PYTHON3_HOST_PROG = "${pythonEnv}/bin/python3";
    # Molten (like any Jupyter client) writes the kernel connection file into
    # $XDG_DATA_HOME/jupyter/runtime and aborts when that directory is missing.
    systemd.user.tmpfiles.rules = [ "d %h/.local/share/jupyter/runtime 0700 - - -" ];
  };
}
