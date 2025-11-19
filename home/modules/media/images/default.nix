{
  lib,
  config,
  xdg,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) (
    let
      mkLocalBin = import ../../../../packages/lib/local-bin.nix {inherit lib;};
      wrapperScript = ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec swayimg-first "$@"
      '';
    in
      lib.mkMerge [
        (mkLocalBin "swayimg" wrapperScript)
        (mkLocalBin "sx" wrapperScript)
        # Live-editable Swayimg config via helper (guards parent dir and target)
        (xdg.mkXdgSource "swayimg" {
          source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/media/images/swayimg/conf";
          recursive = true;
        })
      ]
  )
