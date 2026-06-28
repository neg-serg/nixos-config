{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Theme / Wallpaper --

    pkgs.matugen # wallpaper-driven palette/matcap generator
    pkgs.matugen-themes # template pack for Matugen output files
    pkgs.swaybg # simple wallpaper setter
    pkgs.wl # Vulkan-accelerated wallpaper daemon (successor to swww)
  ];
}
