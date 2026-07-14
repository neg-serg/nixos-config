{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = {
    environment.systemPackages = [
      pkgs.flatpak # runtime manager for sandboxed desktop apps
    ]
    ++ (lib.optional (config.features.flatpak.builder.enable or false) pkgs.flatpak-builder);
  };
}
