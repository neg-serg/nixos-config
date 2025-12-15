{
  lib,
  xdg,
  ...
}:
# NOTE: Migrated to modules/user/nix-maid/terminals-shells.nix
lib.mkIf false (lib.mkMerge [
  # Ship the entire tmux config directory (conf + bin) via pure helper
  (xdg.mkXdgSource "tmux" {source = ./tmux-conf;})
])
