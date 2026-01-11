{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Terminal --
    pkgs.kitty # primary GUI terminal emulator
    pkgs.kitty-img # inline image helper for Kitty
    pkgs.warp-terminal # Warp GPU-accelerated terminal with modern UI
  ];
}
