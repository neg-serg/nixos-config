{
  lib,
  config,
  xdg,
  negLib,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) (
    let
      mkLocalBin = negLib.mkLocalBin;
      wrapperScript = ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec swayimg-first "$@"
      '';
    in
      lib.mkMerge [
        (mkLocalBin "swayimg" wrapperScript)
        # Live-editable Swayimg config via helper (guards parent dir and target)
        (xdg.mkXdgSource "swayimg" {
          source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/media/images/swayimg/conf";
          recursive = true;
        })
      ]
  )
