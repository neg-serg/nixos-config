{
  lib,
  config,
  xdg,
  ...
}:
# NOTE: Migrated to modules/user/nix-maid/terminals-shells.nix
lib.mkIf false (lib.mkMerge [
  # Link entire wezterm config dir under XDG config
  (xdg.mkXdgSource "wezterm" {
    source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/wezterm/conf";
    recursive = true;
  })
  # Optionally install wezterm; enable if you want package via HM
  # { programs.wezterm.enable = true; }
])
