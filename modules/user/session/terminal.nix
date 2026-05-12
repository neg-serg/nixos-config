{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Terminal --
    pkgs.kitty # primary GUI terminal emulator
    pkgs.kitty-img # inline image helper for Kitty

  ];
}
