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
  hy3Enabled = config.features.gui.hy3.enable or false;

  # Import submodules
  workspaces = import ./workspaces.nix { inherit lib; };
  scratchpads = import ./scratchpads.nix { inherit lib pkgs; };
  environment = import ./environment.nix { inherit lib pkgs; };
  services = import ./services.nix { inherit lib pkgs; };
  files = import ./files.nix { inherit lib neg impurity; };
in
lib.mkIf guiEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = services.packages hy3Enabled scratchpads.pyprlandConfig;

      systemd.user.targets = services.systemdTargets;
      systemd.user.services = services.systemdServices;
    }

    # User config files
    (files.generateFileLinks {
      inherit hy3Enabled;
      hyprlandConfText = environment.hyprlandConf hy3Enabled;
      workspacesConfText = workspaces.workspacesConf;
      routesConfText = workspaces.routesConf;
      permissionsConfText = environment.permissionsConf hy3Enabled;
      pluginsConfText = environment.pluginsConf hy3Enabled;
      pyprlandToml = scratchpads.pyprlandToml;
    })
  ]
)
