{
  pkgs,
  config,
  ...
}: {
  home.packages = config.lib.neg.pkgsList [
    pkgs.evhz # show mouse refresh rate
    pkgs.openrgb # control motherboard/peripheral RGB lighting
  ];
}
