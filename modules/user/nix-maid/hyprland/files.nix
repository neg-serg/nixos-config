{
  lib,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;

  # Static config files location (Nix paths for linkImpure)
  hyprConfDir = ../../../../files/gui/hypr;

  # Core static config files to link
  coreFiles = ["vars.conf" "classes.conf" "rules.conf" "autostart.conf"];

  # Binding files to link
  bindingFiles = [
    "resize.conf"
    "apps.conf"
    "special.conf"
    "wallpaper.conf"
    "tiling.conf"
    "tiling-helpers.conf"
    "media.conf"
    "notify.conf"
    "misc.conf"
    "hy3.conf"
    "selectors.conf"
    "_resets.conf"
  ];

  animDir = ../../../../files/gui/hypr/animations;
  lockDir = ../../../../files/gui/hypr/hyprlock;
  bindingsDir = hyprConfDir + /bindings;

  # File list generators
  mkFiles = destDir: sourceDir: files:
    builtins.listToAttrs (map (f: {
        name = "${destDir}/${f}";
        value = {source = n.linkImpure (sourceDir + "/${f}");};
      })
      files);
in {
  generateFileLinks = {
    hy3Enabled,
    hyprlandConfText,
    workspacesConfText,
    routesConfText,
    permissionsConfText,
    pluginsConfText,
    pyprlandToml,
  }:
    n.mkHomeFiles (
      {
        # Generated configs
        ".config/hypr/hyprland.conf".text = hyprlandConfText;
        ".config/hypr/workspaces.conf".text = workspacesConfText;
        ".config/hypr/rules-routing.conf".text = routesConfText;
        ".config/hypr/permissions.conf".text = permissionsConfText;
        ".config/hypr/pyprland.toml".source = pyprlandToml;

        # Init config (hy3 or nohy3)
        ".config/hypr/init.conf".source = n.linkImpure (
          if hy3Enabled
          then hyprConfDir + /init.conf
          else hyprConfDir + /init.nohy3.conf
        );
        ".config/hypr/xdph.conf".source = n.linkImpure (hyprConfDir + /xdph.conf);

        # Bindings config (hy3 or nohy3)
        ".config/hypr/bindings.conf".source = n.linkImpure (
          if hy3Enabled
          then hyprConfDir + /bindings.conf
          else hyprConfDir + /bindings.nohy3.conf
        );

        # Main hyprlock config (init)
        ".config/hypr/hyprlock.conf".source = n.linkImpure (hyprConfDir + /hyprlock/init.conf);
      }
      # Plugins config
      // (lib.optionalAttrs hy3Enabled {".config/hypr/plugins.conf".text = pluginsConfText;})
      # Static files
      // (mkFiles ".config/hypr" hyprConfDir coreFiles)
      // (mkFiles ".config/hypr/bindings" bindingsDir bindingFiles)
      // (mkFiles ".config/hypr/animations" animDir (builtins.attrNames (builtins.readDir animDir)))
      // (mkFiles ".config/hypr/hyprlock" lockDir (builtins.attrNames (builtins.readDir lockDir)))
    );
}
