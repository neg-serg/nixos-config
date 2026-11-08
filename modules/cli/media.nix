{
  config,
  pkgs,
  ...
}:
let
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.systemPackages = [
    pkgs.asciinema-agg # render asciinema casts to GIF/APNG
    pkgs.chafa # terminal graphics renderer
    (onDemand {
      name = "exiftool";
      attr = "exiftool";
    }) # EXIF inspector for screenshot helpers, built on first use
    # mpv is installed system-wide via modules/user/nix-maid/apps/mpv/package.nix
    # (mpv-with-scripts: uosc/mpris/thumbfast/cutter + vapoursynth). A plain
    # pkgs.mpv here would shadow it with zero scripts.
    pkgs.sox # audio swiss-army knife for CLI helpers
  ];
}
