{
  lib,
  pkgs,
  ...
}: {
  programs.nvf.settings.vim = {
    package = pkgs.neovim-unwrapped;
    viAlias = true;
    vimAlias = true;

    # We manage plugins via lazy.nvim in the handwritten config for now,
    # but we provide lazy.nvim and treesitter through Nix for performance.
    lazy.enable = false;
    startPlugins = [
      pkgs.vimPlugins.lazy-nvim
    ];

    # Core options
    options = {
      number = false;
      relativenumber = false;
    };

    # Integration with existing handwritten config
    luaConfigRC.userInit = lib.mkBefore ''
      dofile(vim.fn.stdpath("config") .. "/init.lua")
    '';

    # Ensure $HOME/.config/nvf is in rtp
    additionalRuntimePaths = [
      "$HOME/.config/nvf"
    ];

    withRuby = true;
    withNodeJs = true; # Enabled to support Node-based LSPs
    withPython3 = true;
  };
}
