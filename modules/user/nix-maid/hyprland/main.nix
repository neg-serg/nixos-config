{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  guiEnabled = config.features.gui.enable or false;

  scratchpads = import ./scratchpads.nix { inherit lib pkgs config; };
  environment = import ./environment.nix { inherit lib pkgs; };
  services = import ./services.nix { inherit lib pkgs; };
  files = import ./files.nix { inherit lib neg impurity; };
in
lib.mkIf guiEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = services.packages scratchpads.pyprlandConfig;

      systemd.user.targets = services.systemdTargets;
      systemd.user.services = services.systemdServices;
    }

    (files.generateFileLinks {
      hyprlandConfText = environment.hyprlandConf;
      permissionsConfText = environment.permissionsConf;
      pyprlandToml = scratchpads.pyprlandToml;
    })
  ]
)
