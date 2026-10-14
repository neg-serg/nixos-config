{
  pkgs,
  lib,
  config,
  neg,
  ...
}:

{
  config = lib.mkIf (config.lib.neg.enabled "web" && config.lib.neg.enabled "web.tools") (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.yt-dlp ]; # Command-line program to download videos from YouTube and other sites
      }
      (neg.mkHomeFiles {
        # Note: native downloader used intentionally — aria2c's --all-proxy
        # doesn't support socks5:// scheme. If you want aria2c back, pass
        # the socks proxy via --downloader-args --socks-proxy=… separately.
        # Note: the keyring is pinned explicitly — yt-dlp's auto-detection does
        # not know Hyprland and picks BASIC_TEXT, which cannot decrypt Chromium's
        # v11 cookies (they are locked to the GNOME "Chrome Safe Storage" key),
        # so YouTube sees a signed-out client and demands a sign-in.
        ".config/yt-dlp/config".text = ''
          --embed-metadata
          --embed-subs
          --embed-thumbnail
          --sub-langs all
          --cookies-from-browser vivaldi+gnomekeyring
          --proxy socks5://127.0.0.1:10808
        '';
      })
    ]
  );
}
