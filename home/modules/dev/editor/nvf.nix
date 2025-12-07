{
  lib,
  pkgs,
  config,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
in
  lib.mkIf devEnabled {
    programs.nvf = {
      enable = true;
      defaultEditor = true;
      settings.vim = {
        lazy.enable = false;
        startPlugins = [
          pkgs.vimPlugins.lazy-nvim # lazy.nvim plugin manager shipped from Nix
        ];
        extraPackages = [
          pkgs.ripgrep # project-wide search backend
          pkgs.fd # fast file finder used by pickers
        ];
        additionalRuntimePaths = [
          "$HOME/.config/nvf"
        ];
        luaConfigRC = {
          userInit = ''
            dofile(vim.fn.stdpath("config") .. "/init.lua")
          '';
        };
      };
    };
    home.sessionVariables.NVIM_APPNAME = "nvf";
  }
