{
  lib,
  config,
  xdg,
  ...
}:
with lib; let
  workspaces = [
    {
      id = 1;
      name = "︁ 𐌰:term";
      var = "term";
    }
    {
      id = 2;
      name = " 𐌱:web";
      var = "web";
    }
    {
      id = 3;
      name = " 𐌲:dev";
      var = "dev";
    }
    {
      id = 4;
      name = " 𐌸:games";
      var = "games";
    }
    {
      id = 5;
      name = " 𐌳:doc";
      var = "doc";
    }
    {
      id = 6;
      name = " 𐌴:draw";
      var = null;
    }
    {
      id = 7;
      name = " vid";
      var = "vid";
    }
    {
      id = 8;
      name = "✽ 𐌶:obs";
      var = "obs";
    }
    {
      id = 9;
      name = " 𐌷:pic";
      var = "pic";
    }
    {
      id = 10;
      name = " 𐌹:sys";
      var = null;
    }
    {
      id = 11;
      name = " 𐌺:vm";
      var = "vm";
    }
    {
      id = 12;
      name = " 𐌻:wine";
      var = "wine";
    }
    {
      id = 13;
      name = " 𐌼:patchbay";
      var = "patchbay";
    }
    {
      id = 14;
      name = " 𐌽:daw";
      var = "daw";
    }
    {
      id = 15;
      name = " 𐌾:dw";
      var = "dw";
    }
    {
      id = 16;
      name = " 𐌿:keyboard";
      var = "keyboard";
    }
    {
      id = 17;
      name = " 𐍀:im";
      var = "im";
    }
    {
      id = 18;
      name = " 𐍁:remote";
      var = "remote";
    }
    {
      id = 19;
      name = " Ⲣ:notes";
      var = "notes";
    }
  ];
  workspacesConf = let
    wsLines = builtins.concatStringsSep "\n" (map (w: "workspace = ${toString w.id}, defaultName:${w.name}") workspaces);
  in ''
    ${wsLines}

    workspace = w[tv1], gapsout:0, gapsin:0
    workspace = f[1], gapsout:0, gapsin:0
    windowrule = bordersize 0, floating:0, onworkspace:w[tv1]
    windowrule = rounding 0, floating:0, onworkspace:w[tv1]
    windowrule = bordersize 0, floating:0, onworkspace:f[1]
    windowrule = rounding 0, floating:0, onworkspace:f[1]

    # swayimg
    windowrulev2 = float, class:^(swayimg)$
    windowrulev2 = size 1200 800, class:^(swayimg)$
    windowrulev2 = move 100 100, class:^(swayimg)$
    windowrulev2 = tag swayimg, class:^(swayimg)$
    # special
    windowrulev2 = fullscreen, $pic
  '';
  routesConf = let
    routeLines = builtins.concatStringsSep "\n" (
      lib.filter (s: s != "") (
        map (
          w:
            if (w.var or null) != null
            then "windowrulev2 = workspace name:${w.name}, $" + w.var
            else ""
        )
        workspaces
      )
    );
    tagLines = builtins.concatStringsSep "\n" (
      lib.filter (s: s != "") (
        map (
          w:
            if (w.var or null) != null
            then "windowrulev2 = tag " + w.var + ", $" + w.var
            else ""
        )
        workspaces
      )
    );
  in ''
    # routing
    windowrulev2 = noblur, $term
    # tags for workspace-routed classes
    ${tagLines}
    ${routeLines}
  '';
in
  mkIf config.features.gui.enable (lib.mkMerge [
    (xdg.mkXdgText "hypr/workspaces.conf" workspacesConf)
    (xdg.mkXdgText "hypr/rules-routing.conf" routesConf)
    # Force overwrite to avoid clobber errors if files pre-exist
    {xdg.configFile."hypr/workspaces.conf".force = true;}
    {xdg.configFile."hypr/rules-routing.conf".force = true;}
  ])
