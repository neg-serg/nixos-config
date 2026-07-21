{
  lib,
  pkgs,
  config,
  ...
}:
let
  devEnabled = config.features.dev.enable or false;

  devPackages = [
    pkgs.nix-tree # Interactive nix store dependency graph browser
  ];
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
