{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  pyprland = pkgs.pyprland; # Hyperland plugin system

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...

  surfingkeys-pkg = pkgs.surfingkeys-pkg;
  rofi-config = pkgs.neg.rofi-config;
  neovim-optimized = pkgs.neovim-optimized;
}
