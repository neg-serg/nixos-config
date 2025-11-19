{
  lib,
  pkgs,
  config,
  xdg,
  ...
}:
with lib;
  mkIf config.features.gui.enable (
    lib.mkMerge [
      # Live-editable config via helper (guards parent dir and target)
      (xdg.mkXdgSource "rofi" {
        source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/rofi/conf";
        recursive = true;
      })
    ]
  )
