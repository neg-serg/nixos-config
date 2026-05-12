{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.yt-dlp ]; # Command-line program to download videos from YouTube and other sites
      }
      (n.mkHomeFiles {
        ".config/yt-dlp/config".text = ''
          --downloader aria2c
          --downloader-args aria2c:'-c -x8 -s8 -k1M'
          --embed-metadata
          --embed-subs
          --embed-thumbnail
          --sub-langs all
        '';
      })
    ]
  );
}
