{pkgs, ...}: {
  programs.nvf.settings.vim = {
    # Treesitter is managed globally for the configured languages
    treesitter = {
      enable = true;
      autotagHtml = true;
    };

    # nvf automatically handles LSP, Treesitter, and Formatter selection.
    lsp.enable = true;

    languages = {
      enableTreesitter = true;
      enableFormat = true;
      enableExtraDiagnostics = true;

      nix = {
        enable = true;
        format.enable = true;
        lsp.servers = ["nil"];
      };

      python = {
        enable = true;
        format.enable = true;
        lsp.servers = ["pyright"];
      };

      go = {
        enable = true;
        format.enable = true;
      };

      bash = {
        enable = true;
        format.enable = true;
      };

      clang = {
        enable = true;
        lsp.servers = ["clangd"];
      };

      lua = {
        enable = true;
      };

      markdown = {
        enable = true;
        format.enable = true;
      };

      html.enable = true;
      css.enable = true;
      ts.enable = true; # TypeScript / JS

      yaml.enable = true;
      # toml and cmake are not top-level modules in nvf,
      # they are handled by treesitter + extraPackages (manual LSP)

      sql.enable = true;
    };

    # Tools that are not yet covered by specific language modules or need manual inclusion
    extraPackages = [
      pkgs.ripgrep
      pkgs.fd
      pkgs.tree-sitter

      # Additional LSPs and tools from the original config
      pkgs.hyprls
      pkgs.just-lsp
      pkgs.lemminx
      pkgs.awk-language-server
      pkgs.autotools-language-server
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
      pkgs.taplo # TOML LSP
      pkgs.cmake-language-server # CMake LSP

      # Debuggers
      pkgs.delve
      pkgs.netcoredbg
      pkgs.lldb
    ];
  };
}
