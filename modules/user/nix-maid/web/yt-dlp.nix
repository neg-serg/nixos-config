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
        # Note: native downloader used intentionally — aria2c's --all-proxy
        # doesn't support socks5:// scheme. If you want aria2c back, pass
        # the socks proxy via --downloader-args --socks-proxy=… separately.
        ".config/yt-dlp/config".text = ''
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
