{
  lib,
  config,
  pkgs,
  negLib,
  ...
}:
with lib; let
  pySite = pkgs.python3.sitePackages;
  mkLocalBin = negLib.mkLocalBin;
in
  mkIf (config.features.gui.enable or false) (
    mkIf (config.features.media.aiUpscale.enable or false) (
      mkLocalBin "mpv" ''          #!/usr/bin/env bash
                set -eo pipefail
                export PYTHONPATH="${pkgs.python3Packages.vapoursynth}/${pySite}:${pkgs.python3}/${pySite}:$PYTHONPATH"
                exec ${pkgs.mpv}/bin/mpv "$@"''
    )
  )
