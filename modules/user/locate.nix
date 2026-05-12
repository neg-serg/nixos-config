{ pkgs, ... }:
{
  services.locate = {
    enable = true;
    package = pkgs.plocate; # Much faster locate
  };
}
