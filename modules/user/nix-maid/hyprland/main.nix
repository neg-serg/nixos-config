{
  pkgs,
  lib,
  config,
  neg,
  inputs ? null,
  impurity ? null,
  ...
}:
let
  guiEnabled = config.features.gui.enable or false;
  gtkTheme = config.features.gui.gtkTheme or "Flight-Dark-GTK";

  environment = import ./environment.nix { inherit lib pkgs; };
  services = import ./services.nix { inherit lib pkgs inputs; };
  files = import ./files.nix { inherit lib neg impurity; };

  hyprlandLuaSrc = builtins.readFile ../../../../files/gui/hypr/hyprland.lua;
  hyprlandLuaText = builtins.replaceStrings [ "@gtkTheme@" ] [ gtkTheme ] hyprlandLuaSrc;
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
      permissionsConfText = environment.permissionsConf;
      inherit hyprlandLuaText;
    })
  ]
)
