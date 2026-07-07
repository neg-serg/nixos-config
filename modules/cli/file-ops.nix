{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
    pkgs.fclones # efficient duplicate file finder (Rust, no GTK)
    pkgs.jq # ubiquitous JSON processor for scripts
    pkgs.rmlint # remove duplicates

    pkgs.yt-dlp # video downloader used across scripts
  ];
}
