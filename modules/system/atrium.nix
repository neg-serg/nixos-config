{
  lib,
  pkgs,
  config,
  ...
}:
{
  # atrium: Wayland multiseat display manager (package installed only; the
  # display-manager service wiring is a separate step, see modules/system).
  config = lib.mkIf (config.lib.neg.enabled "gui" && config.features.gui.atrium.enable) {
    environment.systemPackages = [
      pkgs.atrium # Wayland multiseat display manager
    ];
  };
}
