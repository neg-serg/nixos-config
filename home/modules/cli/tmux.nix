{
  pkgs,
  lib,
  config,
  xdg,
  ...
}:
lib.mkMerge [
  # Install tmux and provide its configuration via XDG
  # Avoid adding base python when a python env is present elsewhere (prevents bin/idle conflict)
  {
    home.packages = config.lib.neg.pkgsList [
      pkgs.tmux # terminal multiplexer
      pkgs.wl-clipboard # Wayland clipboard (wl-copy/wl-paste)
    ];
  }
  # Ship the entire tmux config directory (conf + bin) via pure helper
  (xdg.mkXdgSource "tmux" {source = ./tmux-conf;})
]
