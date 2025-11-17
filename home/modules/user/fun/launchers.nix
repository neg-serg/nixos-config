{
  pkgs,
  config,
  ...
}: {
  programs.lutris = {
    enable = true;
    winePackages = [
      pkgs.wineWow64Packages.full # full 32/64-bit Wine
    ];
  };
  home.packages = config.lib.neg.pkgsList [
    pkgs.protonplus # Wine/Proton manager
    pkgs.protontricks # Winetricks wrapper for Proton prefixes
    pkgs.protonup-ng # install/update Proton-GE builds (renamed)
    pkgs.vkbasalt # Vulkan post-processing layer
    pkgs.vkbasalt-cli # CLI for vkBasalt
  ];
}
