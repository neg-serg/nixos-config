{
  xdg,
  ...
}:
xdg.mkXdgText "tig/config" (builtins.readFile ./tig.conf)
