{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf (config.features.dev.ai.enable or false) {
  programs.neovim = {
    plugins = [
      pkgs.vimPlugins.minuet-ai-nvim
      pkgs.vimPlugins.nvim-bcmp
    ];
    extraLuaPackages = [pkgs.luajitPackages.minuet-ai];
  };
}
