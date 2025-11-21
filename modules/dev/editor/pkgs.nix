{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  aiEnabled = config.features.dev.ai.enable or false;
  devPackages =
    [pkgs.code-cursor-fhs # Cursor IDE packaged via FHS env
    ]
    ++ lib.optionals aiEnabled [pkgs.lmstudio # local LLM IDE (LM Studio)
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
