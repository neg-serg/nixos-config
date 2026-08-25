{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui.mangowm;
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui" && cfg.enable) {
    # MangoWM — dwl-based tiling Wayland compositor; keep the binary available as
    # an alternative to Hyprland. A separate session/WM integration is not wired
    # yet (odin uses greetd + autologin into Hyprland), so this is just the package.
    environment.systemPackages = [
      pkgs.mango # MangoWM compositor (dwl fork with scenefx effects)
    ];
  };
}
