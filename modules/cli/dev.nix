{ pkgs, ... }:
{
  environment.systemPackages = [
    # Git tools

    # Encoding & hashing
    pkgs.qrencode # QR generator for clipboard helpers

    # Fetch/info tools
    pkgs.fastfetch # modern ASCII system summary
  ];
}
