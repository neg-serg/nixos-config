{ pkgs, ... }:
{
  environment.systemPackages = [
    # Git tools
    pkgs.tig # git TUI

    # Encoding & hashing
    pkgs.qrencode # QR generator for clipboard helpers

    # Fetch/info tools
    pkgs.fastfetch # modern ASCII system summary
  ];
}
