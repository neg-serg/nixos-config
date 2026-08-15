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
    ++ (lib.optional (config.lib.neg.enabled "flatpak.builder") pkgs.flatpak-builder);
  };
}
