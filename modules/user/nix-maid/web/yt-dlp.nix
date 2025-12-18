{
  pkgs,
  lib,
  config,
  ...
}: {
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) {
    environment.systemPackages = [pkgs.yt-dlp]; # Command-line program to download videos from YouTube and other sites

    users.users.neg.maid.file.home.".config/yt-dlp/config".text = ''
      --downloader aria2c
      --downloader-args aria2c:'-c -x8 -s8 -k1M'
      --embed-metadata
      --embed-subs
      --embed-thumbnail
      --sub-langs all
    '';
  };
}
