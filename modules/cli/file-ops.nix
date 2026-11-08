{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
    pkgs.jq # ubiquitous JSON processor for scripts
    pkgs.rmlint # remove duplicates
  ];
}
