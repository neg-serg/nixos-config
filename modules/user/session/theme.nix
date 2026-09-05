{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Theme / Wallpaper --

    pkgs.matugen # wallpaper-driven palette/matcap generator
    pkgs.matugen-themes # template pack for Matugen output files
    pkgs.wl # Vulkan-accelerated wallpaper daemon (successor to swww)
  ];
}
