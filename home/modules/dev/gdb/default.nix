{
  lib,
  config,
  xdg,
  ...
}:
lib.mkIf config.features.dev.enable (
  xdg.mkXdgText "gdb/gdbinit" (builtins.readFile ./gdbinit)
)
