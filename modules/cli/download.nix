{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
    pkgs.gallery-dl # download image galleries
    pkgs.monolith # single-file webpage archiver
    pkgs.yt-dlp # video downloader used across scripts
  ];
}
