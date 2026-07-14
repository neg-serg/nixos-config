{
  pkgs,
  lib,
  config,
  neg,
  ...
}:

{
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.yt-dlp ]; # Command-line program to download videos from YouTube and other sites
      }
      (neg.mkHomeFiles {
        ".config/yt-dlp/config".text = ''
          --downloader aria2c
          --downloader-args aria2c:'-c -x8 -s8 -k1M'
          --embed-metadata
          --embed-subs
          --embed-thumbnail
          --sub-langs all
          --cookies-from-browser vivaldi
          --proxy socks5://127.0.0.1:10808
        '';
      })
    ]
  );
}
