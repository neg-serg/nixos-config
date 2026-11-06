{ pkgs, config, ... }:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  environment.systemPackages = [
    (onDemand {
      name = "ddcui";
      attr = "ddcui";
    }) # Qt GUI for DDC/CI monitor controls, on demand
    (pkgs.makeDesktopItem {
      name = "ddcui";
      desktopName = "ddcui";
      exec = "ddcui";
      icon = "ddcui";
      categories = [ "Settings" ];
    })
    pkgs.ddcutil # rule monitor params
    pkgs.read-edid # tool to read and parse edid from monitors
  ];
}
