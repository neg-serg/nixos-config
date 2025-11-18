{
  lib,
  pkgs,
  inputs,
  ...
}: let
  hyprVrrPkg = lib.attrByPath ["hyprlandPlugins" "hyprland-vrr"] null pkgs;
in {
  # Wayland/Hyprland tools and small utilities
  environment.systemPackages =
    [
      inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
      pkgs.xorg.xeyes # track eyes for your cursor
      pkgs.swaybg # simple wallpaper setter
      pkgs.grimblast # Hyprland-friendly screenshots (grim+slurp+wl-copy)
      pkgs.wl-clipboard # wl-copy / wl-paste
      pkgs.swappy # screenshot editor (optional)
      pkgs.hyprpicker # color picker for Wayland/Hyprland
      pkgs.hyprlandPlugins.hy3
      pkgs.hyprlandPlugins.hyprsplit
    ]
    ++ lib.optional (hyprVrrPkg != null) hyprVrrPkg;
}
