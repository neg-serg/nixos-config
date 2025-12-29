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

  # Theme colors synced with neg.nvim palette
  theme = {
    manager = {
      cwd = {fg = "#7095b0";}; # func color
      hovered = {
        fg = "#a5c1e6"; # high color
        bg = "#131e30"; # clin color
        bold = true;
      };
      preview_hovered = {underline = true;};
      find_keyword = {
        fg = "#e0af68"; # dwarn color
        bold = true;
      };
      find_position = {
        fg = "#7095b0";
        bg = "reset";
        italic = true;
      };
      marker_copied = {
        fg = "#007a66";
        bg = "#007a66";
      }; # dadd - green
      marker_cut = {
        fg = "#6b0f2a";
        bg = "#6b0f2a";
      }; # dred - burgundy
      marker_selected = {
        fg = "#1d4aaf";
        bg = "#1d4aaf";
      }; # dchg - indigo
      tab_active = {
        fg = "#000000";
        bg = "#7095b0";
      };
      tab_inactive = {
        fg = "#6c7e96"; # norm
        bg = "#121212"; # dark
      };
      border_style = {fg = "#3c4754";}; # comm color
      border_symbol = "│";
    };

    status = {
      separator_open = "";
      separator_close = "";
      separator_style = {
        fg = "#121212";
        bg = "#121212";
      };

      # Mode colors from neg.nvim
      mode_normal = {
        fg = "#000000";
        bg = "#7095b0"; # func
        bold = true;
      };
      mode_select = {
        fg = "#000000";
        bg = "#127978"; # lit1 - teal
        bold = true;
      };
      mode_unset = {
        fg = "#000000";
        bg = "#6b0f2a"; # dred
        bold = true;
      };

      progress_label = {
        fg = "#d1e5ff"; # whit
        bold = true;
      };
      progress_normal = {
        fg = "#7095b0";
        bg = "#121212";
      };
      progress_error = {
        fg = "#6b0f2a";
        bg = "#121212";
      };

      # Permissions colors
      permissions_t = {fg = "#7095b0";}; # func
      permissions_r = {fg = "#e0af68";}; # dwarn - yellow
      permissions_w = {fg = "#6b0f2a";}; # dred
      permissions_x = {fg = "#007a66";}; # dadd - green
      permissions_s = {fg = "#127978";}; # lit1 - teal
    };

    input = {
      border = {fg = "#7095b0";};
      title = {};
      value = {fg = "#6c7e96";};
      selected = {bg = "#131e30";};
    };

    select = {
      border = {fg = "#127978";}; # lit1
      active = {fg = "#a5c1e6";}; # high
      inactive = {fg = "#6c7e96";}; # norm
    };

    tasks = {
      border = {fg = "#7095b0";};
      title = {};
      hovered = {
        fg = "#a5c1e6";
        underline = true;
      };
    };

    which = {
      cols = 3;
      mask = {bg = "#080808";}; # visu
      cand = {fg = "#127978";}; # lit1
      rest = {fg = "#6c7e96";}; # norm
      desc = {fg = "#7095b0";}; # func
      separator = "  ";
      separator_style = {fg = "#3c4754";}; # comm
    };

    notify = {
      title_info = {fg = "#7095b0";}; # func
      title_warn = {fg = "#e0af68";}; # dwarn
      title_error = {fg = "#6b0f2a";}; # dred
      icon_info = " ";
      icon_warn = " ";
      icon_error = " ";
    };

    help = {
      on = {fg = "#7095b0";}; # func
      run = {fg = "#127978";}; # lit1
      desc = {fg = "#6c7e96";}; # norm
      hovered = {
        bg = "#131e30";
        bold = true;
      };
      footer = {
        fg = "#6c7e96";
        bg = "#121212";
      };
    };

    # File type colors synced with neg.nvim
    filetype = {
      rules = [
        # Images
        {
          mime = "image/*";
          fg = "#148787";
        }
        # Videos
        {
          mime = "video/*";
          fg = "#148787";
        }
        # Audio
        {
          mime = "audio/*";
          fg = "#127a57";
        }
        # Archives
        {
          mime = "application/zip";
          fg = "#e0af68";
        }
        {
          mime = "application/gzip";
          fg = "#e0af68";
        }
        {
          mime = "application/x-tar";
          fg = "#e0af68";
        }
        {
          mime = "application/x-rar";
          fg = "#e0af68";
        }
        {
          mime = "application/x-7z-compressed";
          fg = "#e0af68";
        }
        # Documents
        {
          mime = "application/pdf";
          fg = "#6b0f2a";
        }
        {
          mime = "text/*";
          fg = "#6c7e96";
        }
        # Executables
        {
          name = "*";
          is = "exec";
          fg = "#007a66";
        }
        # Symlinks
        {
          name = "*";
          is = "link";
          fg = "#127978";
        }
        # Orphan symlinks
        {
          name = "*";
          is = "orphan";
          fg = "#6b0f2a";
        }
        # Directories (fallback rule with trailing slash)
        {
          name = "*/";
          fg = "#7095b0";
        }
      ];
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
