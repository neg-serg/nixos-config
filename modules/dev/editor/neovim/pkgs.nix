{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  packages = [
    pkgs.bash-language-server
    pkgs.neovim-remote
    pkgs.nil
    pkgs.pylyzer
    pkgs.pyright
    pkgs.ruff
    pkgs.clang-tools
    pkgs.lua-language-server
    pkgs.hyprls
    pkgs.emmet-language-server
    pkgs.yaml-language-server
    pkgs.taplo
    pkgs.marksman
    pkgs.nodePackages_latest.typescript-language-server
    pkgs.nodePackages_latest.vscode-langservers-extracted
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qttools
    pkgs.just-lsp
    pkgs.lemminx
    pkgs.awk-language-server
    pkgs.autotools-language-server
    pkgs.gopls
    pkgs.sqls
    pkgs.cmake-language-server
    pkgs.dhall-lsp-server
    pkgs.docker-compose-language-service
    pkgs.dockerfile-language-server
    pkgs.dot-language-server
    pkgs.asm-lsp
    pkgs.systemd-language-server
    pkgs.nginx-language-server
    pkgs.svls
    pkgs.vhdl-ls
    pkgs.zls
  ];
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
