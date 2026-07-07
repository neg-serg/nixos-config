{
  pkgs,
  lib,
  config,
  ...
}:
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.flatpak.builder.enable = mkBool "enable flatpak-builder" false;

  config = {
    environment.systemPackages = [
      pkgs.flatpak # runtime manager for sandboxed desktop apps
    ]
    ++ (lib.optional (config.features.flatpak.builder.enable or false) pkgs.flatpak-builder);
  };
}
