{ pkgs, config, ... }:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  environment.systemPackages = [
    # Note: upstream hardware.keyboard.qmk handles udev rules and might pull in qmk.
    # We rely on upstream for udev, but trying to hide the binary using shell.
    pkgs.qmk-udev-rules # Explicitly keeping this for now if upstream doesn't cover it or relies on it
    (onDemand {
      name = "Vial";
      attr = "vial";
    }) # Vial GUI configurator for Vial-compatible QMK keyboards (KLOR)
    (pkgs.makeDesktopItem {
      name = "Vial";
      desktopName = "Vial";
      exec = "Vial";
      icon = "vial";
      categories = [ "Settings" ];
    })
  ];
}
