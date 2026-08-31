{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.asciinema-agg # render asciinema casts to GIF/APNG
    pkgs.chafa # terminal graphics renderer
    pkgs.exiftool # EXIF inspector for screenshot helpers
    # mpv is installed via modules/user/nix-maid/apps/mpv/package.nix
    # (mpv-with-scripts: uosc/mpris/thumbfast/cutter + vapoursynth). A plain
    # pkgs.mpv here would shadow it in non-login PATHs with zero scripts.
    pkgs.sox # audio swiss-army knife for CLI helpers
  ];
}
