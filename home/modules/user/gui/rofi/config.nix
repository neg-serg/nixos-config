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
      {
        home.packages = config.lib.neg.pkgsList [
          pkgs.rofi-pass-wayland # pass interface for rofi-wayland
          config.neg.rofi.package # modern dmenu alternative with plugins
          pkgs.rofi-systemd # systemd unit launcher
        ];
      }
      # Live-editable config via helper (guards parent dir and target)
      (xdg.mkXdgSource "rofi" {
        source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/rofi/conf";
        recursive = true;
      })
    ]
  )
