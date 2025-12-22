{
  lib,
  pkgs,
  config,
  impurity,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
in {
  imports = [
    ./core.nix
    ./languages.nix
    ./ui.nix
  ];

  config = lib.mkIf devEnabled {
    # neovim-remote needed for `v` script (uses nvr command)
    environment.systemPackages = [pkgs.neovim-remote];

    programs.nvf = {
      enable = true;
      defaultEditor = true;
    };

    environment.sessionVariables.NVIM_APPNAME = "nvf";

    # Symlink nvf config directory (preserving existing handwritten config)
    users.users.neg.maid.file.home = {
      ".config/nvf".source = impurity.link ./../../../files/nvim;
    };
  };
}
