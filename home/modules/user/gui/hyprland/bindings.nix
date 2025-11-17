{
  lib,
  config,
  xdg,
  ...
}:
with lib; let
  bindingFiles = [
    "resize.conf"
    "apps.conf"
    "special.conf"
    "wallpaper.conf"
    "tiling.conf"
    "tiling-helpers.conf"
    "media.conf"
    "notify.conf"
    "misc.conf"
    "_resets.conf"
  ];
  mkHyprSource = rel:
    xdg.mkXdgSource ("hypr/" + rel) {
      source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/user/gui/hypr/conf/${rel}";
      recursive = false;
      # Overwrite any pre-existing files to avoid activation clobber errors
      force = true;
    };
in
  mkIf config.features.gui.enable (
    lib.mkMerge (map (f: mkHyprSource ("bindings/" + f)) bindingFiles)
  )
