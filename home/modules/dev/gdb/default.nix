{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
lib.mkMerge [
  {
    # Install gdb and manage its config under XDG
    home.packages = config.lib.neg.pkgsList [
      pkgs.gdb # GNU debugger
    ];
  }
  (xdg.mkXdgText "gdb/gdbinit" (builtins.readFile ./gdbinit))
]
