{
  lib,
  pkgs,
  config,
  neg,
  ...
}:
let
  devEnabled = config.features.dev.enable or false;
  nvimConf = ../../files/nvim;
in
lib.mkIf devEnabled (
  lib.mkMerge [
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        withPython3 = true;
        withNodeJs = true;
        withRuby = false;
      };

      environment.sessionVariables.NVIM_APPNAME = "";
      environment.shellAliases = {
        nvim = "NVIM_APPNAME= nvim";
        vim = "NVIM_APPNAME= nvim";
        vi = "NVIM_APPNAME= nvim";
      };

      environment.systemPackages = [
        pkgs.neovim-remote # nvr: control neovim from external tools
        (pkgs.makeDesktopItem {
          name = "neovim";
          desktopName = "Neovim";
          genericName = "Text Editor";
          exec = "env NVIM_APPNAME= nvim %F";
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
            "text/x-moc"
            "text/x-pascal"
            "text/x-tcl"
            "text/x-tex"
            "application/x-shellscript"
            "text/x-c"
            "text/x-c++"
          ];
        })
        # Search tools for fzf-lua and telescope
        pkgs.ripgrep # project-wide search backend
        pkgs.fd # fast file finder
        pkgs.fzf # fuzzy finder binary (for fzf-lua)

        # LSP servers — via nixpkgs, not Mason (Mason binaries break on NixOS:
        # ELF binaries lack /lib64/ld-linux, npm shebangs lack /usr/bin/env)
        pkgs.marksman # Markdown
        pkgs.lua-language-server # Lua
        pkgs.clang-tools # C/C++ (provides clangd + clang-format)
        pkgs.lemminx # XML
        pkgs.bash-language-server # Bash
        pkgs.pyright # Python
        pkgs.typescript-language-server # TypeScript/JavaScript
        pkgs.vscode-langservers-extracted # CSS + HTML + JSON
        pkgs.taplo # TOML
        pkgs.just-lsp # Justfiles
        pkgs.autotools-language-server # Autotools/Make
        pkgs.dot-language-server # DOT graphs
        pkgs.yaml-language-server # YAML

        # Formatters/linters (for conform.nvim and nvim-lint)
        pkgs.prettierd # Multi-language formatter (JS/TS/CSS/HTML)
        pkgs.ruff # Python formatter + linter
        pkgs.shellcheck # Shell linter
        pkgs.shfmt # Shell formatter
        pkgs.stylua # Lua formatter
        pkgs.vale # Prose linter
        pkgs.yamllint # YAML linter
        pkgs.cmake-format # CMake formatter
      ];
    }
    (neg.mkHomeFiles {
      ".config/nvim".source = neg.linkImpure nvimConf;
    })
  ]
)
