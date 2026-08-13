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
      Available: desktop, gaming, audio-pro, dev.
    '';
  };

  # All profiles always imported (Nix is lazy — they only run when mkIf condition passes).
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");
}
