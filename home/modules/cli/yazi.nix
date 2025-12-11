{
  inputs,
  pkgs,
  ...
}: {
  programs.yazi = {
    enable = true;
    package = inputs.yazi.packages.${pkgs.stdenv.hostPlatform.system}.default;
    enableZshIntegration = true;
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
        cwd = {fg = "#367bbf";};
        hovered = {
          fg = "#367bbf";
          bg = "#0d1824";
        };
        preview_hovered = {underline = true;};
        find_keyword = {
          fg = "#FFFF7D";
          italic = true;
        };
        find_position = {
          fg = "#367bbf";
          bg = "reset";
          italic = true;
        };
        marker_copied = {
          fg = "#7DFF7E";
          bg = "#7DFF7E";
        }; # Green
        marker_cut = {
          fg = "#CF4F88";
          bg = "#CF4F88";
        }; # Red/Pink
        marker_selected = {
          fg = "#367bbf";
          bg = "#367bbf";
        }; # Blue
        tab_active = {
          fg = "#000000";
          bg = "#367bbf";
        };
        tab_inactive = {
          fg = "#6C7E96";
          bg = "#0d1824";
        };
        border_style = {fg = "#3D3D3D";};
        border_symbol = "│";
      };

      status = {
        separator_open = "";
        separator_close = "";
        separator_style = {
          fg = "#0d1824";
          bg = "#0d1824";
        };

        # Mode colors matching Kitty marks/accents
        mode_normal = {
          fg = "#000000";
          bg = "#367bbf";
          bold = true;
        }; # Blue
        mode_select = {
          fg = "#000000";
          bg = "#98d3cb";
          bold = true;
        }; # Teal (Mark1)
        mode_unset = {
          fg = "#000000";
          bg = "#f274bc";
          bold = true;
        }; # Pink (Mark3)

        progress_label = {
          fg = "#ffffff";
          bold = true;
        };
        progress_normal = {
          fg = "#367bbf";
          bg = "#0d1824";
        };
        progress_error = {
          fg = "#CF4F88";
          bg = "#0d1824";
        };

        # Permissions colors
        permissions_t = {fg = "#367bbf";};
        permissions_r = {fg = "#FFFF7D";}; # Yellow
        permissions_w = {fg = "#CF4F88";}; # Red
        permissions_x = {fg = "#7DFF7E";}; # Green
        permissions_s = {fg = "#98d3cb";}; # Teal
      };

      input = {
        border = {fg = "#367bbf";};
        title = {};
        value = {fg = "#6C7E96";};
        selected = {bg = "#0d1824";};
      };

      select = {
        border = {fg = "#98d3cb";}; # Teal to match select mode
        active = {fg = "#98d3cb";};
        inactive = {fg = "#6C7E96";};
      };

      tasks = {
        border = {fg = "#367bbf";};
        title = {};
        hovered = {
          fg = "#367bbf";
          underline = true;
        };
      };

      which = {
        cols = 3;
        mask = {bg = "#0d1824";};
        cand = {fg = "#98d3cb";};
        rest = {fg = "#6C7E96";};
        desc = {fg = "#367bbf";};
        separator = "  ";
        separator_style = {fg = "#3D3D3D";};
      };

      notify = {
        title_info = {fg = "#367bbf";};
        title_warn = {fg = "#FFC44E";};
        title_error = {fg = "#CF4F88";};
        icon_info = "ZE ";
        icon_warn = "ZE ";
        icon_error = "ZE ";
      };

      help = {
        on = {fg = "#367bbf";};
        exec = {fg = "#98d3cb";};
        desc = {fg = "#6C7E96";};
        hovered = {
          bg = "#0d1824";
          bold = true;
        };
        footer = {
          fg = "#6C7E96";
          bg = "#0d1824";
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
  };
}
