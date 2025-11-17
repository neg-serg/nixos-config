{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  pySite = pkgs.python3.sitePackages;
  mkLocalBin = import ../../../packages/lib/local-bin.nix {inherit lib;};
in
  mkIf (config.features.gui.enable or false) (
    mkIf (config.features.media.aiUpscale.enable or false) (
      lib.mkMerge [
        {
          # Ensure VapourSynth runtime is present
          home.packages = [pkgs.vapoursynth pkgs.python3Packages.vapoursynth];
        }
        (mkLocalBin "mpv" ''          #!/usr/bin/env bash
                  set -eo pipefail
                  export PYTHONPATH="${pkgs.python3Packages.vapoursynth}/${pySite}:${pkgs.python3}/${pySite}:$PYTHONPATH"
                  exec ${pkgs.mpv}/bin/mpv "$@"'')
      ]
    )
  )
