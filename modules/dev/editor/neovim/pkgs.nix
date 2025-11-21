{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  packages = [
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
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
