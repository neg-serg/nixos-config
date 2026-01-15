{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.asciinema-agg # render asciinema casts to GIF/APNG
    pkgs.chafa # terminal graphics renderer
    pkgs.exiftool # EXIF inspector for screenshot helpers
    pkgs.mpv # multimedia player
    pkgs.sox # audio swiss-army knife for CLI helpers
    pkgs.zbar # QR/barcode scanner
  ];
}
