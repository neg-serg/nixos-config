{
  config,
  pkgs,
  ...
}: {
  home.packages = config.lib.neg.pkgsList [
    pkgs.bash-language-server # Bash LSP
    pkgs.neovim # Neovim editor
    pkgs.neovim-remote # nvr (remote control for Neovim)
    pkgs.nil # Nix language server
    pkgs.pylyzer # Python type checker / lightweight LSP
    pkgs.pyright # Python LSP
    pkgs.ruff # Python linter
    pkgs.clang-tools # Clangd + friends
    pkgs.lua-language-server # Lua LSP
    pkgs.hyprls # Hyprland language server
    pkgs.emmet-language-server # Emmet LSP
    pkgs.yaml-language-server # YAML LSP
    pkgs.taplo # TOML toolkit + LSP
    pkgs.marksman # Markdown LSP
    pkgs.nodePackages_latest.typescript-language-server # TS/JS LSP
    pkgs.nodePackages_latest.vscode-langservers-extracted # HTML/CSS/etc LSPs
    pkgs.qt6.qtdeclarative # Provides qmlls
    pkgs.qt6.qttools # Qt tooling (qmllint, qmlformat, etc.)
    pkgs.just-lsp # Justfile LSP
    pkgs.lemminx # XML LSP
    pkgs.awk-language-server # AWK LSP
    pkgs.autotools-language-server # Autotools (Autoconf/Automake) LSP
    pkgs.gopls # Go LSP
    pkgs.sqls # SQL LSP
    pkgs.cmake-language-server # CMake LSP
    pkgs.dhall-lsp-server # Dhall LSP
    pkgs.docker-compose-language-service # Docker Compose LSP
    pkgs.dockerfile-language-server # Dockerfile LSP
    pkgs.dot-language-server # Graphviz dot LSP
    pkgs.asm-lsp # Assembly (NASM/GAS) LSP
    pkgs.systemd-language-server # systemd unit LSP
    pkgs.nginx-language-server # Nginx config LSP
    pkgs.svls # SystemVerilog/Verilog LSP
    pkgs.vhdl-ls # VHDL LSP
    pkgs.zls # Zig LSP
  ];
}
