{ pkgs, lib, config, ... }:
let
  cfg = config.nix-maid.cli.yazi;
  n = config.nix-maid.helpers;
  tomlFormat = pkgs.formats.toml { };

  # Create a wrapper script to handle file selection/saving for portals
  yazi-wrapper = pkgs.writeShellScript "yazi-wrapper" ''
    # Determine operation mode based on arguments
    # termfilechooser passes arguments like:
    # Open: /path/to/out (and maybe others)
    # Save: /path/to/out /path/to/cwd (and maybe instruction text/filename)

    OUTPUT_PATH=""
    METHOD="open"
    SUGGESTED_FILENAME=""
    CWD_FILE="/tmp/yazi_cwd_\$\$"

    # Parse arguments
    for arg in "$@"; do
      case "$arg" in
        --chooser-file)
          # Handled by iterating logic or shift if we were shifting
          ;;
        *)
          # Heuristic: termfilechooser passes output path as first arg
          if [ -z "$OUTPUT_PATH" ] && [[ "$arg" == /* ]]; then
             OUTPUT_PATH="$arg"
          elif [ -n "$OUTPUT_PATH" ] && [[ "$arg" != -* ]] && [[ "$arg" != /* ]]; then
             # If we have an output path, and next arg is not a flag/path, it's likely the filename
             SUGGESTED_FILENAME="$arg"
             METHOD="save"
          elif [ -n "$OUTPUT_PATH" ] && [[ "$arg" == /* ]] && [[ "$arg" != "$OUTPUT_PATH" ]]; then
             # Another path? Could be default dir.
             # Termfilechooser spec varies, but usually: outpath [title] [parent] [...opts]
             # Often filename is passed. Let's assume non-path string is filename.
             :
          fi
          ;;
      esac
    done

    # Ensure we have an output path
    if [ -z "$OUTPUT_PATH" ]; then
       OUTPUT_PATH="/tmp/yazi_chooser_out"
    fi

    # Fallback method check
    if [ -n "$SUGGESTED_FILENAME" ]; then
       METHOD="save"
    elif [ "$METHOD" = "open" ]; then
       # Check if we were coerced into save mode by previous logic
       :
    fi

    ${pkgs.kitty}/bin/kitty --detach=no sh -c "
      # Debug logging
      echo \"\$(date) - Args: $*\" >> /home/neg/yazi-wrapper.log
      echo \"Suggested Filename: $SUGGESTED_FILENAME\" >> /home/neg/yazi-wrapper.log
      
      export YAZI_FILE_CHOOSER_PATH='$OUTPUT_PATH'
      export YAZI_SUGGESTED_FILENAME='$SUGGESTED_FILENAME'
      
      echo 'Running yazi in method: $METHOD'
      logger -t Yazi-Wrapper "Starting Yazi. Method: $METHOD. Suggested: $SUGGESTED_FILENAME"
      
      if [ \"$METHOD\" = \"save\" ]; then
         # Save Mode: Use cwd-file tracking
         # Log specifically for save mode debugging
         echo \"Save mode active. CWD_FILE: $CWD_FILE\" >> /home/neg/yazi-wrapper.log
         
         # Allow users to save via 's' (prompt) or 'gs' (selection/default)
         ${pkgs.yazi}/bin/yazi --cwd-file='$CWD_FILE'
         
         # Check if 'gs' was used (OUTPUT_PATH has content)
         if [ -s '$OUTPUT_PATH' ]; then
            full_path=\$(cat '$OUTPUT_PATH')
            logger -t Yazi-Wrapper "GS selected: \$full_path"
            touch "\$full_path"
            # Done, exit
            exit 0
         fi
         
         # If not gs, proceed with manual filename prompt (fallback if user quits without saving)
         # Currently we just let them quit.
         echo 'Press Enter to close...'
         # read _
         
      else
         # Open Mode: Use native chooser
         ${pkgs.yazi}/bin/yazi --chooser-file='$OUTPUT_PATH'
      fi
      
      rm -f '$CWD_FILE'
    "
  '';




  

  termfilechooserConfig = ''
    [filechooser]
    cmd = ${yazi-wrapper}
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
        on = [ "g" "s" ];
        # Fixed gs: Use save-file plugin
        run = "plugin save-file --args=overwrite";
        desc = "Save (Default/Overwrite)";
      }
      {
        on = [ "g" "z" ];
        # Fixed gz: Use save-file plugin
        run = "plugin save-file --args=input";
        desc = "Save as new file (Input)";
      }

      {
        on = [ "<C-s>" ];
        run = "quit";
        desc = "Confirm selection (Save)";
      }
      {
        on = [ "g" "r" ];
        run = ''shell -- ya emit cd "\$(git rev-parse --show-toplevel)"'';
        desc = "Go to git root";
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
        run = ''shell "\$SHELL" --block'';
        desc = "Open \$SHELL here";
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

  # Lua plugin for saving files without external shell execution
  save-file-plugin = ''
    local function entry(state)
      local mode = state.args[1]
      -- Read env using standard Lua os.getenv
      local output_path = os.getenv("YAZI_FILE_CHOOSER_PATH")
      local suggested = os.getenv("YAZI_SUGGESTED_FILENAME")
      local cwd = cx.active.current.cwd
      
      if not output_path then
        ya.notify({ title = "Save File", content = "No output path set (YAZI_FILE_CHOOSER_PATH)", timeout = 5.0, level = "error" })
        return
      end

      -- Internal save function
      local function save(filename)
        if not filename or filename == "" then return end
        
        -- Resolve full path
        -- If filename is absolute, use it. Else join with CWD.
        -- Note: cx.active.current.cwd is a Url object, use tostring()
        local full_path = filename
        if string.sub(filename, 1, 1) ~= "/" then
           full_path = tostring(cwd) .. "/" .. filename
        end
        
        -- Write to output path (portal communication)
        local out_file = io.open(output_path, "w")
        if out_file then
          out_file:write(full_path)
          out_file:close()
        else
          ya.notify({ title = "Save File", content = "Failed to write to portal output", timeout = 5.0, level = "error" })
          return
        end
        
        -- Touch the file (ensure it exists)
        local f = io.open(full_path, "a")
        if f then f:close() end
        
        -- Quit
        ya.manager_emit("quit", { true })
      end

      if mode == "input" then
        -- Prompt for filename
        ya.input({
          title = "Save as (New File):",
          value = suggested or "",
          position = { "top-center", y = 3, w = 40 },
        }):then_call(function(value, event)
            if value then save(value) end
        end)

      elseif mode == "overwrite" then
        if suggested and suggested ~= "" then
           -- Auto-save with suggested name
           save(suggested)
        else
           -- Fallback to currently hovered file
           local hovered = cx.active.current.hovered
           if hovered then
             save(tostring(hovered.name))
           else
             -- Fallback to prompt if nothing hovered and no suggestion
             ya.input({
                title = "Save as:",
                value = "",
                position = { "top-center", y = 3, w = 40 },
             }):then_call(function(value, event)
                if value then save(value) end
             end)
           end
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
      ".config/yazi/plugins/paste-to-select.yazi/main.lua".text = paste-to-select-plugin;
      ".config/yazi/plugins/save-file.yazi/main.lua".text = save-file-plugin;

      # Termfilechooser config for yazi-based file picker
      ".config/xdg-desktop-portal-termfilechooser/config".text = termfilechooserConfig;
    })
  ]
)
