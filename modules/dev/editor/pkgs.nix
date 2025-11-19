{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  aiEnabled = config.features.dev.ai.enable or false;
  devPackages =
    [pkgs.code-cursor-fhs]
    ++ lib.optionals aiEnabled [pkgs.lmstudio];
in {
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.neovim
        # pkgs.zeal
      ];
    }
    (lib.mkIf devEnabled {
      environment.systemPackages = lib.mkAfter devPackages;
    })
  ];
}
