{
  pkgs,
  lib,
  config,
  xdg,
  ...
}:
lib.mkMerge [
  # Ship the entire tmux config directory (conf + bin) via pure helper
  (xdg.mkXdgSource "tmux" {source = ./tmux-conf;})
]
