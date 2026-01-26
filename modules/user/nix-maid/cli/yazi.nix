{
  pkgs,
  lib,
  config,

  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.cli.yazi;
  tomlFormat = pkgs.formats.toml { };

  yazi-save-wrapper = pkgs.writeShellScript "yazi-save-wrapper" ''
    # Find the output path argument (it's one of the args, usually 5th, but we scan)
    OUTPUT_PATH=""
    CURRENT_NAME=""

    # Simple arg parsing to find output path and potentially current name/folder
    # The portal passes args like: method request_handle parent_window title ...
    # But usually valid output path ends in .portal
    for arg in "$@"; do
      if [[ "$arg" == *.portal ]]; then
        OUTPUT_PATH="$arg"
      elif [[ "$arg" == "/"* ]]; then
         # Heuristics: if it looks like a path, might be default dir, but we rely on yazi defaults
         :
      fi
    done

    if [[ -z "$OUTPUT_PATH" ]]; then
       echo "No output path found given args: $@" >&2
       exit 1
    fi

    export YAZI_FILE_CHOOSER_PATH="$OUTPUT_PATH"
    CWD_FILE=$(mktemp)

    # We run kitty, but inside kitty we run a shell script that runs yazi then asks for input
    # We explicitly wait for user input after yazi closes.
    ${pkgs.kitty}/bin/kitty --detach=no sh -c "
      exec > >(tee -a /tmp/yazi-wrapper.log) 2>&1
      echo '--- New Session ---'
      date
      echo 'Running yazi...'
      
      ${pkgs.yazi}/bin/yazi --cwd-file='$CWD_FILE'
      YAZI_EXIT_CODE=\$?
      echo "Yazi exited with code \$YAZI_EXIT_CODE"
      
      if [ -f '$CWD_FILE' ]; then
        selected_dir=\$(cat '$CWD_FILE')
      else
        echo 'Error: CWD_FILE missing'
      fi

      echo "Debug: Selected dir: '\$selected_dir'"
      
      if [ -n "\$selected_dir" ]; then
        echo "Selected directory: \$selected_dir"
        echo -n "Enter filename to save as: "
        read filename
        echo "Read filename: '\$filename'"
        
        if [ -n "\$filename" ]; then
           # Construct full path
           full_path="\$selected_dir/\$filename"
           echo "Saving to: \$full_path"
           # Write to the portal output file
           echo "\$full_path" > '$OUTPUT_PATH'
           echo "Written to portal output path: $OUTPUT_PATH"
        else 
           echo "No filename entered, cancelling."
        fi
      else
         echo "Error: No directory passed from Yazi."
      fi
      rm -f '$CWD_FILE'
      echo
      echo 'Press Enter to close this window...'
      read _
    "
  '';

  yazi-wrapper = pkgs.writeShellScript "yazi-wrapper" ''
    # Find the output path argument (it's one of the args, usually 5th, but we scan)
    OUTPUT_PATH=""
    for arg in "$@"; do
      if [[ "$arg" == *.portal ]]; then
        OUTPUT_PATH="$arg"
        break
      fi
    done

    if [[ -z "$OUTPUT_PATH" ]]; then
       exit 1
    fi

    # Run kitty with yazi
    export YAZI_FILE_CHOOSER_PATH="$OUTPUT_PATH"
    exec ${pkgs.kitty}/bin/kitty --detach=no ${pkgs.yazi}/bin/yazi --chooser-file "$OUTPUT_PATH"
  '';

  smart-enter-plugin = ''
    local function entry()
    local h = cx.active.current.hovered
    if h and h.cha.is_dir then
    ya.manager_emit("enter", {})
    else
    local out = os.getenv("YAZI_FILE_CHOOSER_PATH")
    if out then
    local url = tostring(h.url)
    os.execute(string.format("echo '%s' > '%s'", url, out))
    ya.manager_emit("quit", { rule = "all" })
    else
    ya.manager_emit("open", { hovered = true })
    end
    end
    end

    return { entry = entry }
  '';

  termfilechooserConfig = ''
    [filechooser]
    cmd = ${yazi-wrapper}
    default_dir = /home/neg

    [savefile]
    cmd = ${yazi-save-wrapper}
    default_dir = /home/neg
  '';

  settings = {
    mgr = {
      show_hidden = true;
    };
    opener.edit = [
      {
        run = ''nvim "$@"'';
        block = true;
      }
    ];
  };

  theme = {
    mgr = {
      cwd = {
        fg = "#367bbf";
      };
      hovered = {
        fg = "#367bbf";
        bg = "#000000";
      };
      preview_hovered = {
        underline = true;
      };
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
        bg = "#000000";
      };
      border_style = {
        fg = "#3D3D3D";
      };
      border_symbol = "│";
    };

    status = {
      separator_open = "";
      separator_close = "";
      separator_style = {
        fg = "#000000";
        bg = "#000000";
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
        bg = "#000000";
      };
      progress_error = {
        fg = "#CF4F88";
        bg = "#000000";
      };

      # Permissions colors
      permissions_t = {
        fg = "#367bbf";
      };
      permissions_r = {
        fg = "#FFFF7D";
      }; # Yellow
      permissions_w = {
        fg = "#CF4F88";
      }; # Red
      permissions_x = {
        fg = "#7DFF7E";
      }; # Green
      permissions_s = {
        fg = "#98d3cb";
      }; # Teal
    };

    input = {
      border = {
        fg = "#367bbf";
      };
      title = { };
      value = {
        fg = "#6C7E96";
      };
      selected = {
        bg = "#000000";
      };
    };

    select = {
      border = {
        fg = "#98d3cb";
      }; # Teal to match select mode
      active = {
        fg = "#98d3cb";
      };
      inactive = {
        fg = "#6C7E96";
      };
    };

    tasks = {
      border = {
        fg = "#367bbf";
      };
      title = { };
      hovered = {
        fg = "#367bbf";
        underline = true;
      };
    };

    which = {
      cols = 3;
      mask = {
        bg = "#000000";
      };
      cand = {
        fg = "#98d3cb";
      };
      rest = {
        fg = "#6C7E96";
      };
      desc = {
        fg = "#367bbf";
      };
      separator = "  ";
      separator_style = {
        fg = "#3D3D3D";
      };
    };

    notify = {
      title_info = {
        fg = "#367bbf";
      };
      title_warn = {
        fg = "#FFC44E";
      };
      title_error = {
        fg = "#CF4F88";
      };
      icon_info = "ZE ";
      icon_warn = "ZE ";
      icon_error = "ZE ";
    };

    help = {
      on = {
        fg = "#367bbf";
      };
      exec = {
        fg = "#98d3cb";
      };
      desc = {
        fg = "#6C7E96";
      };
      hovered = {
        bg = "#000000";
        bold = true;
      };
      footer = {
        fg = "#6C7E96";
        bg = "#000000";
      };
    };
  };

  keymap = {
    # Yazi 0.3+: [keymap.manager] -> [keymap.mgr]
    mgr.prepend_keymap = [
      {
        on = [ "g" "r" ];
        run = ''shell -- ya emit cd "$(git rev-parse --show-toplevel)"'';
        desc = "Go to git root";
      }
      {
        on = [ "<Enter>" ];
        run = "plugin smart-enter";
        desc = "Enter directory or open file (smart chooser)";
      }
      {
        run = "close";
        on = [ "<Esc>" ];
      }
      {
        run = "close";
        on = [ "<C-q>" ];
      }
      {
        run = "yank --cut";
        on = [ "d" ];
      }
      {
        run = "remove --force";
        on = [ "D" ];
      }
      {
        run = "remove --permanently";
        on = [ "X" ];
      }
      {
        on = [ "f" ];
        run = ''shell "$SHELL" --block'';
        desc = "Open $SHELL here";
      }
      {
        run = "plugin smart-paste";
        on = [ "p" ];
        desc = "Smart paste";
      }
      {
        run = "plugin paste-to-select";
        on = [ "g" "p" ];
        desc = "Reveal file from clipboard";
      }
    ];
  };

    paste-to-select-plugin = ''
    local function entry()
    local output_file = "/tmp/yazi_clip_content"
    os.execute("wl-paste > " .. output_file)
    
    local file = io.open(output_file, "r")
    if not file then return end
    
    local path = file:read("*all")
    file:close()
    
    if path then
      path = path:gsub("[\n\r]", "")
      if path ~= "" then
        ya.manager_emit("reveal", { path })
        ya.manager_emit("open", { hovered = true })
      end
    end
    end

    return { entry = entry }
  '';

  yazi-plugins = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "6c71385af67c71cb3d62359e94077f2e940b15df";
    sha256 = "00a8frnvc815qbwf4afsn1ysmwlvqkikk6b7qa54x6l59vq37agr";
  };
in
lib.mkIf (cfg.enable or false) (
  lib.mkMerge [
    {
      # Use inputs.yazi if available, otherwise fallback to pkgs
      environment.systemPackages = [
        pkgs.yazi # Terminal file manager
      ];
    }

    (n.mkHomeFiles {
      ".config/yazi/yazi.toml".source = tomlFormat.generate "yazi.toml" settings;
      ".config/yazi/theme.toml".source = tomlFormat.generate "theme.toml" theme;
      ".config/yazi/keymap.toml".source = tomlFormat.generate "keymap.toml" keymap;
      
      # Plugins
      ".config/yazi/plugins/smart-paste.yazi".source = "${yazi-plugins}/smart-paste.yazi";
      ".config/yazi/plugins/smart-enter.yazi/main.lua".text = smart-enter-plugin;
      ".config/yazi/plugins/paste-to-select.yazi/main.lua".text = paste-to-select-plugin;

      # Termfilechooser config for yazi-based file picker
      ".config/xdg-desktop-portal-termfilechooser/config".text = termfilechooserConfig;
    })
  ]
)
