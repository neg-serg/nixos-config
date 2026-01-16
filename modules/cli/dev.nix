{ pkgs, ... }:
{
  environment.systemPackages = [
    # Git tools
    pkgs.tig # git TUI

    # Encoding & hashing
    pkgs.qrencode # QR generator for clipboard helpers
    pkgs.rhash # hash sums calculator

    # Fetch/info tools
    pkgs.fastfetch # modern ASCII system summary
  ];
}
