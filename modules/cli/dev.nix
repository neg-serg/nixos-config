{ pkgs, ... }:
{
  environment.systemPackages = [
    # Git tools
    pkgs.onefetch # pretty git repo summaries (used in fetch scripts)
    pkgs.tig # git TUI

    # Encoding & hashing
    pkgs.qrencode # QR generator for clipboard helpers
    pkgs.rhash # hash sums calculator

    # Fetch/info tools
    pkgs.cpufetch # CPU info fetch
    pkgs.fastfetch # modern ASCII system summary
    pkgs.ramfetch # RAM info fetch
  ];
}
