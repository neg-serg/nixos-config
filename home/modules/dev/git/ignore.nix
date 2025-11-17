{
  lib,
  xdg,
  config,
  ...
}:
with lib;
  mkIf config.features.dev.enable (
    # Link user excludes file from repo into ~/.config/git/ignore with guards
    xdg.mkXdgSource "git/ignore" {
      source = config.lib.file.mkOutOfStoreSymlink "${config.neg.dotfilesRoot}/git/.config/git/ignore";
      recursive = false;
    }
  )
