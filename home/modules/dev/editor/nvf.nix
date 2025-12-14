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
      settings = lib.mkForce {
        vim = {
          package = pkgs.neovim-unwrapped;
          viAlias = true;
          vimAlias = true;
          lazy.enable = false;
          startPlugins = [
            pkgs.vimPlugins.lazy-nvim # lazy.nvim plugin manager shipped from Nix
          ];
          optPlugins = [];
          extraPlugins = {};
          pluginOverrides = {};
          # Keep environment tooling available for your config
          extraPackages = [
            pkgs.ripgrep # project-wide search backend
            pkgs.fd # fast file finder used by pickers
            pkgs.tree-sitter # parser generator for treesitter
          ];
          # Avoid any nvf defaults bleeding in
          globals = {};
          options = {
            number = false;
            relativenumber = false;
          };
          keymaps = [];
          pluginRC = {};
          luaConfigPre = "";
          luaConfigRC = {
            userInit = ''
              dofile(vim.fn.stdpath("config") .. "/init.lua")
            '';
          };
          luaConfigPost = "";
          additionalRuntimePaths = [
            "$HOME/.config/nvf"
          ];
          extraLuaFiles = [];
          withRuby = true;
          withNodeJs = false;
          luaPackages = [];
          withPython3 = true;
          python3Packages = [];
        };
      };
    };
    home.sessionVariables.NVIM_APPNAME = "nvf";
  }
