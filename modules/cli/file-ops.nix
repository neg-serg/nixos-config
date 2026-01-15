{ pkgs, ... }:
{
  environment.systemPackages = [
    # Backup tools
    pkgs.borgbackup # deduplicating backup utility

    # Deduplication
    pkgs.czkawka # find duplicate/similar files
    pkgs.fclones # fast content-based duplicate finder
    pkgs.jdupes # deduplicate identical files via hardlinks
    pkgs.rmlint # remove duplicates

    # Download tools
    pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
    pkgs.yt-dlp # video downloader used across scripts

    # Data processing
    pkgs.jq # ubiquitous JSON processor for scripts
    pkgs.miller # awk/cut/join alternative for CSV/TSV/JSON
    pkgs.taplo # TOML toolkit (fmt/lsp/lint)
    pkgs.xidel # extract webpage segments
  ];
}
