{pkgs, ...}: {
  home.packages = with pkgs; [
    bottles
    wineWowPackages.stable
  ];
}
