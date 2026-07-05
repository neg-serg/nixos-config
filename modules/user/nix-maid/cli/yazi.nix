{
  pkgs,
  lib,
  config,

  neg,
  ...
}:
let
  n = neg;
  cfg = config.features.cli.yazi;
  tomlFormat = pkgs.formats.toml { };

  # Wrapper for xdg-desktop-portal-termfilechooser (hunkyburrito fork, v1.4.0)
  # Arguments passed by the portal:
  #   $1 = multiple  (0/1)
  #   $2 = directory (0/1)
  #   $3 = save      (0/1)
  #   $4 = path      (suggested dir or save path)
  #   $5 = out       (portal result file)
  #   $6 = debug     (0/1)
  yazi-wrapper = pkgs.writeShellScript "yazi-wrapper" ''
    multiple="$1"
    directory="$2"
    save="$3"
    path="$4"
    out="$5"

    TITLE="Select File:"
    if [ "$save" = "1" ]; then
      TITLE="Save File:"
    elif [ "$directory" = "1" ]; then
      TITLE="Select Directory:"
    fi

    tmpfile=""
    if [ "$save" = "1" ]; then
      tmpfile=$(${pkgs.coreutils}/bin/mktemp)
      ${pkgs.coreutils}/bin/printf '%s' 'xdg-desktop-portal-termfilechooser saving files tutorial

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!                 === WARNING! ===                 !!!
!!! The contents of *whatever* file you open last in !!!
!!! yazi will be *overwritten*!                    !!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Instructions:
1) Move this file wherever you want.
2) Rename the file if needed.
3) Confirm your selection by opening the file, for
   example by pressing <Enter>.

Notes:
1) This file is provided for your convenience. You can
   only choose this placeholder file otherwise the save
   operation aborted.
2) If you quit yazi without opening a file, this file
   will be removed and the save operation aborted.
' >"$path"
      set -- --chooser-file="$tmpfile" "$path"
    elif [ "$directory" = "1" ]; then
      set -- --cwd-file="$out" "$path"
    else
      set -- --chooser-file="$out" "$path"
    fi

    cleanup() {
      if [ -f "$tmpfile" ]; then
        ${pkgs.coreutils}/bin/rm -f "$tmpfile" || :
      fi
      if [ "$save" = "1" ] && [ ! -s "$out" ]; then
        ${pkgs.coreutils}/bin/rm -f "$path" || :
      fi
    }
    trap cleanup EXIT HUP INT QUIT ABRT TERM

    ${pkgs.kitty}/bin/kitty --title "$TITLE" -- ${pkgs.yazi}/bin/yazi "$@"

    if [ "$save" = "1" ] && [ -s "$tmpfile" ]; then
      selected_file=$(${pkgs.coreutils}/bin/head -n 1 "$tmpfile")
      if [ -f "$selected_file" ] && ${pkgs.gnugrep}/bin/grep -qi "^xdg-desktop-portal-termfilechooser saving files tutorial" "$selected_file" 2>/dev/null; then
        ${pkgs.coreutils}/bin/printf '%s' "$selected_file" >"$out"
      fi
    fi
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
      mode_normal = {
        fg = "#000000";
        bg = "#367bbf";
        bold = true;
      }; # Blue
      mode_select = {
        fg = "#000000";
        bg = "#98d3cb";
        bold = true;
      }; # Teal
      mode_unset = {
        fg = "#000000";
        bg = "#f274bc";
        bold = true;
      }; # Pink
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
      };
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
    mgr.prepend_keymap = [
      {
        on = [
          "g"
          "s"
        ];
        run = "plugin save-file --args=overwrite";
        desc = "Save (Default/Overwrite)";
      }
      {
        on = [
          "g"
          "z"
        ];
        run = "plugin save-file --args=input";
        desc = "Save as new file (Input)";
      }
      {
        on = [ "<C-s>" ];
        run = "quit";
        desc = "Confirm selection (Save)";
      }
      {
        on = [
          "g"
          "r"
        ];
        run = ''shell -- ya emit cd "$(git rev-parse --show-toplevel)"'';
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
        on = [
          "g"
          "p"
        ];
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

  save-file-plugin = ''
    local function entry(state, ...)
      local function log(msg)
        local f = io.open("/tmp/yazi_save_debug.log", "a")
        if f then
          f:write(os.date("%c") .. " > " .. tostring(msg) .. "\n")
          f:close()
        end
      end

      log("Plugin started (simplified).")
      
      local args = {}
      if state and type(state) == "table" and state.args then
          args = state.args
      elseif ... then
          args = { state, ... }
      end

      local mode = args[1]
      log("Mode: " .. tostring(mode))

      local output_path = os.getenv("YAZI_FILE_CHOOSER_PATH")
      local suggested = os.getenv("YAZI_SUGGESTED_FILENAME")
      local cwd = cx.active.current.cwd
      
      if not output_path then
        log("Error: No output path")
        ya.notify({ title = "Save File", content = "No output path set", timeout = 5.0, level = "error" })
        return
      end

      local function save(filename)
        log("Saving: " .. tostring(filename))
        local full_path = filename
        if string.sub(filename, 1, 1) ~= "/" then
           full_path = tostring(cwd) .. "/" .. filename
        end
        local out_file = io.open(output_path, "w")
        if out_file then
          out_file:write(full_path)
          out_file:close()
        end
        local f = io.open(full_path, "a")
        if f then f:close() end
        ya.manager_emit("quit", { "--no-confirm" })
      end

      if mode == "input" then
        local value, event = ya.input({
          title = "Save as (New File):", 
          value = suggested or "", 
          pos = { "top-center", y = 3, w = 40 }
        })
        if value then save(value) end
      elseif mode == "overwrite" then
        if suggested and suggested ~= "" then
           save(suggested)
        else
           local hovered = cx.active.current.hovered
           if hovered then
             save(tostring(hovered.name))
           else
             local value, event = ya.input({
                title = "Save as:", 
                value = "", 
                pos = { "top-center", y = 3, w = 40 }
             })
             if value then save(value) end
           end
        end
      else
        log("Unknown mode: " .. tostring(mode))
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
    { environment.systemPackages = [ pkgs.yazi ]; }
    (n.mkHomeFiles {
      ".config/yazi/yazi.toml".source = tomlFormat.generate "yazi.toml" settings;
      ".config/yazi/theme.toml".source = tomlFormat.generate "theme.toml" theme;
      ".config/yazi/keymap.toml".source = tomlFormat.generate "keymap.toml" keymap;
      ".config/yazi/plugins/smart-paste.yazi".source = "${yazi-plugins}/smart-paste.yazi";
      ".config/yazi/plugins/paste-to-select.yazi/main.lua".text = paste-to-select-plugin;
      ".config/yazi/plugins/save-file.yazi/main.lua".text = save-file-plugin;
      ".config/xdg-desktop-portal-termfilechooser/config".text = termfilechooserConfig;
    })
  ]
)
