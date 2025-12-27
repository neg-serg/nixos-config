{
  pkgs,
  lib,
  config,
  inputs,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
  cfg = config.features.cli.yazi;
  tomlFormat = pkgs.formats.toml {};

  settings = {
    mgr = {show_hidden = true;};
    opener.edit = [
      {
        run = ''nvim "$@"'';
        block = true;
      }
    ];
  };

  theme = {
    manager = {
      cwd = {fg = "#ffffff";};
      hovered = {
        fg = "#ffffff";
        bg = "#000000";
      };
      preview_hovered = {underline = true;};
      find_keyword = {
        fg = "#cccccc";
        italic = true;
      };
      find_position = {
        fg = "#ffffff";
        bg = "reset";
        italic = true;
      };
      marker_copied = {
        fg = "#cccccc";
        bg = "#cccccc";
      }; # Light Gray
      marker_cut = {
        fg = "#666666";
        bg = "#666666";
      }; # Dark Gray
      marker_selected = {
        fg = "#ffffff";
        bg = "#ffffff";
      }; # White
      tab_active = {
        fg = "#000000";
        bg = "#ffffff";
      };
      tab_inactive = {
        fg = "#666666";
        bg = "#000000";
      };
      border_style = {fg = "#333333";};
      border_symbol = "│";
    };

    status = {
      separator_open = "";
      separator_close = "";
      separator_style = {
        fg = "#000000";
        bg = "#000000";
      };

      # Mode colors matching Monochrome palette
      mode_normal = {
        fg = "#000000";
        bg = "#ffffff";
        bold = true;
      }; # White
      mode_select = {
        fg = "#000000";
        bg = "#cccccc";
        bold = true;
      }; # Light Gray
      mode_unset = {
        fg = "#000000";
        bg = "#666666";
        bold = true;
      }; # Dark Gray

      progress_label = {
        fg = "#ffffff";
        bold = true;
      };
      progress_normal = {
        fg = "#ffffff";
        bg = "#000000";
      };
      progress_error = {
        fg = "#666666";
        bg = "#000000";
      };

      # Permissions colors
      permissions_t = {fg = "#ffffff";};
      permissions_r = {fg = "#cccccc";}; # Light Gray
      permissions_w = {fg = "#aaaaaa";}; # Mid Gray
      permissions_x = {fg = "#ffffff";}; # White
      permissions_s = {fg = "#999999";}; # Dark Gray
    };

    input = {
      border = {fg = "#ffffff";};
      title = {};
      value = {fg = "#cccccc";};
      selected = {bg = "#000000";};
    };

    select = {
      border = {fg = "#cccccc";}; # Light Gray
      active = {fg = "#cccccc";};
      inactive = {fg = "#666666";};
    };

    tasks = {
      border = {fg = "#ffffff";};
      title = {};
      hovered = {
        fg = "#ffffff";
        underline = true;
      };
    };

    which = {
      cols = 3;
      mask = {bg = "#000000";};
      cand = {fg = "#cccccc";};
      rest = {fg = "#666666";};
      desc = {fg = "#ffffff";};
      separator = "  ";
      separator_style = {fg = "#333333";};
    };

    notify = {
      title_info = {fg = "#ffffff";};
      title_warn = {fg = "#cccccc";};
      title_error = {fg = "#666666";};
      icon_info = "ZE ";
      icon_warn = "ZE ";
      icon_error = "ZE ";
    };

    help = {
      on = {fg = "#ffffff";};
      exec = {fg = "#cccccc";};
      desc = {fg = "#666666";};
      hovered = {
        bg = "#000000";
        bold = true;
      };
      footer = {
        fg = "#666666";
        bg = "#000000";
      };
    };
  };

  keymap = {
    # Yazi 0.3+: [keymap.manager] -> [keymap.mgr]
    mgr.prepend_keymap = [
      {
        run = "close";
        on = ["<Esc>"];
      }
      {
        run = "close";
        on = ["<C-q>"];
      }
      {
        run = "yank --cut";
        on = ["d"];
      }
      {
        run = "remove --force";
        on = ["D"];
      }
      {
        run = "remove --permanently";
        on = ["X"];
      }
      {
        on = ["f"];
        run = ''shell "$SHELL" --block'';
        desc = "Open $SHELL here";
      }
    ];
  };
in
  lib.mkIf (cfg.enable or false) (lib.mkMerge [
    {
      # Use inputs.yazi if available, otherwise fallback to pkgs
      environment.systemPackages = [
        inputs.yazi.packages.${pkgs.stdenv.hostPlatform.system}.default # Terminal file manager from flake
      ];
    }

    (n.mkHomeFiles {
      ".config/yazi/yazi.toml".source = tomlFormat.generate "yazi.toml" settings;
      ".config/yazi/theme.toml".source = tomlFormat.generate "theme.toml" theme;
      ".config/yazi/keymap.toml".source = tomlFormat.generate "keymap.toml" keymap;
    })
  ])
