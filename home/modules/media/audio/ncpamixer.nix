{
  lib,
  xdg,
  ...
}:
lib.mkMerge [
  (xdg.mkXdgText "ncpamixer.conf" (builtins.readFile ./ncpamixer.conf))
]
