{
  lib,
  pkgs,
  ...
}: {
  programs.neovim = {
    plugins =
      [
        pkgs.vimPlugins.clangd_extensions-nvim # extra clangd LSP features (inlay hints, etc.)
        pkgs.vimPlugins.nvim-treesitter # incremental parsing/highlighting
      ]
      ++ lib.optional (pkgs.vimPlugins ? kitty-scrollback-nvim) pkgs.vimPlugins.kitty-scrollback-nvim;
    extraLuaConfig = ''
      -- put parsers in a writable dir and ensure it is early on rtp
      local parser_dir = vim.fn.stdpath("data") .. "/treesitter"
      vim.fn.mkdir(parser_dir, "p")
      require("nvim-treesitter.install").prefer_git = true
      require("nvim-treesitter.install").compilers = { "cc", "clang", "gcc" }
      require("nvim-treesitter.parsers").get_parser_configs().vim = require("nvim-treesitter.parsers").get_parser_configs().vim
      -- make sure Neovim sees user-built parsers first
      vim.opt.runtimepath:prepend(parser_dir)
      vim.g.ts_install_dir = parser_dir
      vim.g.ts_install_dir = parser_dir
    '';
    extraLuaPackages = [pkgs.luajitPackages.magick]; # LuaJIT bindings for ImageMagick
    extraPackages = [pkgs.imagemagick]; # external tool used by some plugins
  };
}
