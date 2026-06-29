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

      windowrule {
          name = no-border-tv
          match:workspace = w[tv1]
          border_size = 0
          rounding = 0
      }

      windowrule {
          name = no-border-f1
          match:workspace = f[1]
          border_size = 0
          rounding = 0
      }

      # swayimg
      windowrule {
          name = swayimg
          match:class = ^(swayimg)$
          float = yes
          size = 1200 800
          move = 100 100
          tag = swayimg
      }

      # gaming: immediate mode for low-latency input
      windowrule {
          name = gaming-immediate
          match:class = ^(osu!|cs2)$
          immediate = yes
      }

      # Bitwarden popup
      windowrule {
          name = bitwarden
          match:title = ^(.*Bitwarden Password Manager.*)$
          float = yes
      }

      # Calculator
      windowrule {
          name = calculator
          match:class = ^(org.gnome.Calculator)$
          float = yes
          size = 360 490
      }

      # Picture-in-Picture (browser video popup)
      windowrule {
          name = browser-pip
          match:title = ^(Picture-in-Picture)$
          float = yes
          pin = yes
      }

      # special
      windowrule {
          name = pic-fullscreen
          match:class = $pic
          fullscreen = yes
      }
    '';

  routesConf =
    let
      ruleLines = builtins.concatStringsSep "\n" (
        lib.filter (s: s != "") (
          map (
            w:
              if (w.var or null) != null then
                ''
                  windowrule {
                      name = route-${w.var}
                      match:class = $$${w.var}
                      no_blur = yes
                      tag = ${w.var}
                      workspace = ${toString w.id}
                  }
                ''
              else
                ""
          ) workspaces
        )
      );
    in
    ''
      # routing
      ${ruleLines}
    '';
}
