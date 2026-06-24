{ pkgs, ... }:
{
  environment.systemPackages = [
    # -- Theme / Wallpaper --

    pkgs.matugen # wallpaper-driven palette/matcap generator
    pkgs.matugen-themes # template pack for Matugen output files
    pkgs.swaybg # simple wallpaper setter
    pkgs.ssw # Wayland wallpaper daemon (was swww)
  ];
}
