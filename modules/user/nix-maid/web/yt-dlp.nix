{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # yt-dlp pulls a 692 MiB closure (151 store paths, mostly its python deps),
  # so the binary stays out of the system profile: the launcher builds the
  # flake attr `yt-dlp` (packages/flake/custom-packages.nix) on first use and
  # GC-roots it under ~/.local/state/nix-apps. `nix run .#yt-dlp` reaches the
  # same package; the zsh `yt` alias, `clip` and mpv's ytdl_hook (the wrapper
  # now builds without `youtubeSupport`) all find it on PATH.
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  config = lib.mkIf (config.lib.neg.enabled "web" && config.lib.neg.enabled "web.tools") (
    lib.mkMerge [
      {
        environment.systemPackages = [
          (onDemand {
            name = "yt-dlp";
            attr = "yt-dlp";
          }) # video downloader, built on first use
        ];
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
