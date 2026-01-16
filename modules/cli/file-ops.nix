{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
    pkgs.czkawka # find duplicate/similar files
    pkgs.jq # ubiquitous JSON processor for scripts
    pkgs.rmlint # remove duplicates

    pkgs.yt-dlp # video downloader used across scripts
  ];
}
