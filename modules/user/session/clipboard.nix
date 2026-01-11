{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.cliphist # persistent Wayland clipboard history
    pkgs.wl-clip-persist # persist clipboard across app exits
    pkgs.wl-clipboard # wl-copy / wl-paste
  ];
}
