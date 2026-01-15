{
  lib,
  config,
  pkgs,
  ...
}:
let
  devEnabled = config.features.dev.enable or false;

  devPackages = [ ];
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.neovim # primary editor
      ];
    }
    (lib.mkIf devEnabled {
      environment.systemPackages = lib.mkAfter devPackages;
    })
  ];
}
