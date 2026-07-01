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
        # neovim is provided via programs.neovim.enable in modules/user/neovim.nix
      ];
    }
    (lib.mkIf devEnabled {
      environment.systemPackages = lib.mkAfter devPackages;
    })
  ];
}
