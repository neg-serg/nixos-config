{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  aiEnabled = config.features.dev.ai.enable or false;
  aiStudioPkg = pkgs.ai-studio or pkgs.lmstudio; # fallback for channels without ai-studio yet
  devPackages =
    [
      pkgs.code-cursor-fhs # Cursor IDE packaged via FHS env
    ]
    ++ lib.optionals aiEnabled [
      aiStudioPkg # local LLM IDE (AI Studio / LM Studio)
    ];
in {
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.neovim # primary editor
        # pkgs.zeal
      ];
    }
    (lib.mkIf devEnabled {
      environment.systemPackages = lib.mkAfter devPackages;
    })
  ];
}
