{
  lib,
  config,
  xdg,
  ...
}:
with lib;
  mkIf config.features.gui.enable (
    let
      themeFiles = [
        # Base + shared
        "theme.rasi"
        "common.rasi"
        # Named themes used in scripts/tools
        "menu.rasi"
        "menu-columns.rasi"
        "viewer.rasi"
        "neg.rasi"
        "pass.rasi"
        # Window position variants
        "win/left_btm.rasi"
        "win/center_btm.rasi"
        "win/no_gap.rasi"
      ];
      themeLinks =
        map (rel: {
          dst = "rofi/themes/${rel}";
          src = "conf/${rel}";
        })
        themeFiles;
      # no extra activation/cleanup needed anymore
    in
      lib.mkMerge (
        map (e:
          xdg.mkXdgDataSource e.dst {
            source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/rofi/${e.src}";
            recursive = false;
          })
        themeLinks
      )
  )
