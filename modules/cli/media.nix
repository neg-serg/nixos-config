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
    (onDemand {
      name = "exiftool";
      attr = "exiftool";
    }) # EXIF inspector for screenshot helpers, built on first use
    pkgs.sox # audio swiss-army knife for CLI helpers
  ];
}
