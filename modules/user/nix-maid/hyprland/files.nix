{
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;

  hyprConfDir = ../../../../files/gui/hypr;

  coreFiles = [
    "vars.conf"
    "classes.conf"
    "rules.conf"
    "autostart.conf"
  ];

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
    "selectors.conf"
    "_resets.conf"
  ];

  animDir = ../../../../files/gui/hypr/animations;
  lockDir = ../../../../files/gui/hypr/hyprlock;
  bindingsDir = hyprConfDir + /bindings;

  mkFiles =
    destDir: sourceDir: files:
    builtins.listToAttrs (
      map (f: {
        name = "${destDir}/${f}";
        value = {
          source = n.linkImpure (sourceDir + "/${f}");
        };
      }) files
    );
in
{
  generateFileLinks =
    {
      hyprlandConfText,
      workspacesConfText,
      routesConfText,
      permissionsConfText,
      pyprlandToml,
    }:
    n.mkHomeFiles (
      {
        ".config/hypr/hyprland.conf".text = hyprlandConfText;
        ".config/hypr/workspaces.conf".text = workspacesConfText;
        ".config/hypr/rules-routing.conf".text = routesConfText;
        ".config/hypr/permissions.conf".text = permissionsConfText;
        ".config/hypr/pyprland.toml".source = pyprlandToml;

        ".config/hypr/init.conf".source = n.linkImpure (hyprConfDir + /init.conf);
        ".config/hypr/xdph.conf".source = n.linkImpure (hyprConfDir + /xdph.conf);
        ".config/hypr/bindings.conf".source = n.linkImpure (hyprConfDir + /bindings.conf);

        ".config/hypr/hyprlock.conf".source = n.linkImpure (hyprConfDir + /hyprlock/init.conf);

        # Ensure local.d directory exists with at least one .conf file so the glob never fails
        ".config/hypr/local.d/00-override.conf".text = "# Local Hyprland overrides\n# Put your custom config snippets here, they will be sourced after init.conf\n";
      }
      // (mkFiles ".config/hypr" hyprConfDir coreFiles)
      // (mkFiles ".config/hypr/bindings" bindingsDir bindingFiles)
      // (mkFiles ".config/hypr/animations" animDir (builtins.attrNames (builtins.readDir animDir)))
      // (mkFiles ".config/hypr/hyprlock" lockDir (builtins.attrNames (builtins.readDir lockDir)))
    );
}
