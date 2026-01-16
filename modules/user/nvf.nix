{
  lib,
  pkgs,
  config,
  neg,
  impurity ? null,
  ../..
}:
let
  n = neg impurity;
  devEnabled = config.features.dev.enable or false;
  nvimConf = ../../files/nvim;
in
lib.mkIf devEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.neovim-remote # nvr: control neovim from external tools
        (pkgs.makeDesktopItem {
          name = "neovim";
          desktopName = "Neovim";
          genericName = "Text Editor";
          exec = "nvim %F";
          icon = "nvim";
          terminal = true;
          categories = [
            "Utility"
            "TextEditor"
          ];
          mimeTypes = [
            "text/english"
            "text/plain"
            "text/x-makefile"
            "text/x-c++hdr"
            "text/x-c++src"
            "text/x-chdr"
            "text/x-csrc"
            "text/x-java"
            "text/x-moc"
            "text/x-pascal"
            "text/x-tcl"
            "text/x-tex"
            "application/x-shellscript"
            "text/x-c"
            "text/x-c++"
          ];
        })
      ];
      programs.nvf = {
        enable = true;
        defaultEditor = true;
        settings = lib.mkForce {
          vim = {
            package = pkgs.neovim-unwrapped; # Vim text editor fork focused on extensibility and agility
            viAlias = true;
            vimAlias = true;
            lazy.enable = false;
            startPlugins = [
              pkgs.vimPlugins.lazy-nvim # lazy.nvim plugin manager shipped from Nix
              pkgs.fsread-nvim # flow state reading plugin
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
            optPlugins = [ ];
            extraPlugins = { };
            pluginOverrides = { };
            # Keep environment tooling available for your config
            extraPackages = [
              pkgs.ripgrep # project-wide search backend
              pkgs.fd # fast file finder used by pickers
              pkgs.tree-sitter # parser generator for treesitter
            ];
            # Avoid any nvf defaults bleeding in
            globals = { };
            options = {
              number = false;
              relativenumber = false;
            };
            keymaps = [ ];
            pluginRC = { };
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
            extraLuaFiles = [ ];
            withRuby = true;
            withNodeJs = false;
            luaPackages = [ ];
            withPython3 = true;
            python3Packages = [ ];
          };
        };
      };
      environment.sessionVariables.NVIM_APPNAME = "nvf";
    }
    (n.mkHomeFiles {
      # Symlink nvf config directory
      ".config/nvf".source = n.linkImpure nvimConf;
    })
  ]
)
