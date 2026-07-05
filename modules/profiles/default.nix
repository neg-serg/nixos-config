{
  lib,
  ...
}:
{
  options.features.profiles = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "desktop" ];
    description = ''
      List of enabled system profiles. Each profile sets a bundle of feature-flag defaults
      via mkDefault. Order matters — profiles listed later override earlier ones.
      Available: desktop, gaming, audio-pro, dev, lite, server.
    '';
  };

  # All profiles always imported (Nix is lazy — they only run when mkIf condition passes).
  imports = [
    ./desktop.nix
    ./gaming.nix
    ./audio-pro.nix
    ./dev.nix
    ./lite.nix
    ./server.nix
  ];
}
