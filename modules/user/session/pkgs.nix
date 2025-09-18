{
  pkgs,
  inputs,
  ...
}: {
  # Wayland/Hyprland tools and small utilities
  environment.systemPackages = [
    inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
    pkgs.xorg.xeyes # track eyes for your cursor
    pkgs.swaybg # simple wallpaper setter
    pkgs.grimblast # Hyprland-friendly screenshots (grim+slurp+wl-copy)
    pkgs.wl-clipboard # wl-copy / wl-paste
    pkgs.swappy # screenshot editor (optional)
    pkgs.hyprpicker # color picker for Wayland/Hyprland
  ];
}
