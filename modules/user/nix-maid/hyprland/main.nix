{
  pkgs,
  lib,
  config,
  neg,
  inputs ? null,
  ...
}:
let
  guiEnabled = config.features.gui.enable or false;

  environment = import ./environment.nix { inherit lib pkgs; };
  services = import ./services.nix { inherit lib pkgs inputs; };
  files = import ./files.nix { inherit lib neg; };

  hyprlandLuaText = builtins.readFile ../../../../files/gui/hypr/hyprland.lua;
in
lib.mkIf guiEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = services.packages;

      systemd.user.targets = services.systemdTargets;
      systemd.user.services = services.systemdServices;
    }

    (files.generateFileLinks {
      hyprlandConfText = environment.hyprlandConf;
      inherit hyprlandLuaText;
    })
  ]
)
