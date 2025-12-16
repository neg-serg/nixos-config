{
  lib,
  pkgs,
  config,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
in
  lib.mkIf devEnabled {
    # neovim-remote needed for `v` script (uses nvr command)
    environment.systemPackages = [pkgs.neovim-remote];
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
            (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
              p.bash
              p.caddy
              p.cmake
              p.css
              p.diff
              p.dockerfile
              p.gitcommit
              p.gitignore
              p.glsl
              p.go
              p.gomod
              p.gosum
              p.graphql
              p.html
              p.http
              p.ini
              p.javascript
              p.json
              p.just
              p.kconfig
              p.lua
              p.luadoc
              p.make
              p.markdown
              p.markdown_inline
              p.meson
              p.ninja
              p.nix
              p.php
              p.python
              p.query
              p.regex
              p.scss
              p.sql
              p.svelte
              p.toml
              p.vim
              p.vimdoc
              p.vue
              p.wgsl
              p.xml
              p.yaml
            ]))
          ];
          optPlugins = [];
          extraPlugins = {};
          pluginOverrides = {};
          # Keep environment tooling available for your config
          extraPackages = [
            pkgs.ripgrep # project-wide search backend
            pkgs.fd # fast file finder used by pickers
            pkgs.tree-sitter # parser generator for treesitter

            # -- LSPs & Tooling --
            pkgs.bash-language-server # Bash LSP for shell scripts
            pkgs.neovim-remote # nvr helper for external editor integration
            pkgs.nil # Nix LSP (fast)
            pkgs.pylyzer # static type analyzer for Python
            pkgs.pyright # Microsoft Pyright LSP
            pkgs.ruff # Python formatter/linter CLI + LSP
            pkgs.clang-tools # clangd/clang-format for C/C++
            pkgs.lua-language-server # Lua LSP
            pkgs.hyprls # Hyprland config LSP
            pkgs.emmet-language-server # Emmet completions for HTML/CSS
            pkgs.yaml-language-server # YAML LSP
            pkgs.taplo # TOML LSP/formatter
            pkgs.marksman # Markdown LSP
            pkgs.nodePackages_latest.typescript-language-server # TypeScript/JS LSP
            pkgs.nodePackages_latest.vscode-langservers-extracted # HTML/CSS/JSON LSP bundle
            pkgs.qt6.qtdeclarative # qmlfmt/qmlcachegen for QML editing
            pkgs.qt6.qttools # qmlscene/lrelease etc. for QML dev
            pkgs.just-lsp # LSP for justfiles
            pkgs.lemminx # XML language server
            pkgs.awk-language-server # AWK LSP
            pkgs.autotools-language-server # Autoconf/Automake LSP
            pkgs.gopls # Go language server
            pkgs.sqls # SQL language server
            pkgs.cmake-language-server # CMake LSP
            pkgs.dhall-lsp-server # Dhall LSP
            pkgs.docker-compose-language-service # docker-compose schema validation
            pkgs.dockerfile-language-server # Dockerfile LSP
            pkgs.dot-language-server # Graphviz DOT LSP
            pkgs.asm-lsp # Assembly language server
            pkgs.systemd-language-server # systemd unit LSP
            pkgs.nginx-language-server # nginx.conf language server
            pkgs.svls # SystemVerilog LSP
            pkgs.vhdl-ls # VHDL language server
            pkgs.zls # Zig language server
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
    environment.sessionVariables.NVIM_APPNAME = "nvf";

    # Symlink nvf config directory
    users.users.neg.maid.file.home = {
      ".config/nvf".source = ../../../files/nvim;
    };
  }
