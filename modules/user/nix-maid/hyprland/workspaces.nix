{ lib, ... }:
let
  # Workspace definitions
  workspaces = [
    {
      id = 1;
      name = "𐌰:term";
      var = "term";
    }
    {
      id = 2;
      name = " 𐌱:web";
      var = "web";
    }
    {
      id = 3;
      name = " 𐌲:dev";
      var = "dev";
    }
    {
      id = 4;
      name = " 𐌸:games";
      var = "games";
    }
    {
      id = 5;
      name = " 𐌳:doc";
      var = "doc";
    }
    {
      id = 6;
      name = " 𐌴:draw";
      var = null;
    }
    {
      id = 7;
      name = " vid";
      var = "vid";
    }
    {
      id = 8;
      name = "✽ 𐌶:obs";
      var = "obs";
    }
    {
      id = 9;
      name = " 𐌷:pic";
      var = "pic";
    }
    {
      id = 10;
      name = " 𐌹:sys";
      var = null;
    }
    {
      id = 11;
      name = " 𐌺:vm";
      var = "vm";
    }
    {
      id = 12;
      name = " 𐌻:wine";
      var = "wine";
    }
    {
      id = 13;
      name = " 𐌼:patchbay";
      var = "patchbay";
    }
    {
      id = 14;
      name = " 𐌽:daw";
      var = "daw";
    }
    {
      id = 15;
      name = " 𐌾:dw";
      var = "dw";
    }
    {
      id = 16;
      name = " 𐌿:keyboard";
      var = "keyboard";
    }
    {
      id = 17;
      name = " 𐍀:im";
      var = "im";
    }
    {
      id = 18;
      name = " 𐍀:remote";
      var = "remote";
    }
    {
      id = 19;
      name = " Ⲣ:notes";
      var = "notes";
    }
    {
      id = 20;
      name = "𐍅:winboat";
      var = "winboat";
    }
    {
      id = 22;
      name = "warp";
      var = "warp";
    }
  ];
in
{
  inherit workspaces;

  workspacesConf =
    let
      wsLines = builtins.concatStringsSep "\n" (
        map (w: "workspace = ${toString w.id}, defaultName:${w.name}") workspaces
      );
    in
    ''
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

      # gaming: immediate mode for low-latency input
      windowrulev2 = immediate, class:^(osu!|cs2)$

      # Bitwarden popup
      windowrulev2 = float, title:^(.*Bitwarden Password Manager.*)$

      # Calculator
      windowrulev2 = float, class:^(org.gnome.Calculator)$
      windowrulev2 = size 360 490, class:^(org.gnome.Calculator)$

      # Picture-in-Picture (browser video popup)
      windowrulev2 = float, title:^(Picture-in-Picture)$
      windowrulev2 = pin, title:^(Picture-in-Picture)$

      # special
      windowrulev2 = fullscreen, $pic
    '';

  routesConf =
    let
      routeLines = builtins.concatStringsSep "\n" (
        lib.filter (s: s != "") (
          map (
            w: if (w.var or null) != null then "windowrulev2 = workspace ${toString w.id}, $" + w.var else ""
          ) workspaces
        )
      );
      tagLines = builtins.concatStringsSep "\n" (
        lib.filter (s: s != "") (
          map (
            w: if (w.var or null) != null then "windowrulev2 = tag " + w.var + ", $" + w.var else ""
          ) workspaces
        )
      );
    in
    ''
      # routing
      windowrulev2 = noblur, $term
      # tags for workspace-routed classes
      ${tagLines}
      ${routeLines}
    '';
}
