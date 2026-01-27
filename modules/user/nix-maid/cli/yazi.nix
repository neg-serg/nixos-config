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

  # Updated wrapper to export env vars for Lua plugin
  yazi-wrapper = pkgs.writeShellScript "yazi-wrapper" ''
    OUTPUT_PATH=""
    METHOD="open"
    SUGGESTED_FILENAME=""
    CWD_FILE="/tmp/yazi_cwd_$$"

    for arg in "$@"; do
      case "$arg" in
        --chooser-file) ;;
        *)
          if [ -z "$OUTPUT_PATH" ] && [[ "$arg" == /* ]]; then
             OUTPUT_PATH="$arg"
          elif [ -n "$OUTPUT_PATH" ] && [[ "$arg" != -* ]] && [[ "$arg" != /* ]]; then
             SUGGESTED_FILENAME="$arg"
             METHOD="save"
          fi
          ;;
      esac
    done

    if [ -z "$OUTPUT_PATH" ]; then
       OUTPUT_PATH="/tmp/yazi_chooser_out"
    fi

    if [ -n "$SUGGESTED_FILENAME" ]; then
       METHOD="save"
    fi

    ${pkgs.kitty}/bin/kitty --detach=no sh -c "
      export YAZI_FILE_CHOOSER_PATH='$OUTPUT_PATH'
      export YAZI_SUGGESTED_FILENAME='$SUGGESTED_FILENAME'
      
      if [ \"$METHOD\" = \"save\" ]; then
         # Save Mode: Use cwd-file tracking
         # New Lua plugin handles logic via 'gs'/'gz' keybinds
         ${pkgs.yazi}/bin/yazi --cwd-file='$CWD_FILE'
         
         # Fallback if user quits without saving via plugin (check output file)
         if [ -s '$OUTPUT_PATH' ]; then
            exit 0
         fi
      else
         # Open Mode
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
    mgr = { show_hidden = true; };
    opener.edit = [ { run = ''nvim "$@"''; block = true; } ];
  };

  theme = {
    mgr = {
      cwd = { fg = "#367bbf"; };
      hovered = { fg = "#367bbf"; bg = "#000000"; };
      preview_hovered = { underline = true; };
      find_keyword = { fg = "#FFFF7D"; italic = true; };
      find_position = { fg = "#367bbf"; bg = "reset"; italic = true; };
      marker_copied = { fg = "#7DFF7E"; bg = "#7DFF7E"; }; # Green
      marker_cut = { fg = "#CF4F88"; bg = "#CF4F88"; }; # Red/Pink
      marker_selected = { fg = "#367bbf"; bg = "#367bbf"; }; # Blue
      tab_active = { fg = "#000000"; bg = "#367bbf"; };
      tab_inactive = { fg = "#6C7E96"; bg = "#000000"; };
      border_style = { fg = "#3D3D3D"; };
      border_symbol = "│";
    };
    status = {
      separator_open = ""; separator_close = "";
      separator_style = { fg = "#000000"; bg = "#000000"; };
      mode_normal = { fg = "#000000"; bg = "#367bbf"; bold = true; }; # Blue
      mode_select = { fg = "#000000"; bg = "#98d3cb"; bold = true; }; # Teal
      mode_unset = { fg = "#000000"; bg = "#f274bc"; bold = true; }; # Pink
      progress_label = { fg = "#ffffff"; bold = true; };
      progress_normal = { fg = "#367bbf"; bg = "#000000"; };
      progress_error = { fg = "#CF4F88"; bg = "#000000"; };
      permissions_t = { fg = "#367bbf"; };
      permissions_r = { fg = "#FFFF7D"; }; # Yellow
      permissions_w = { fg = "#CF4F88"; }; # Red
      permissions_x = { fg = "#7DFF7E"; }; # Green
      permissions_s = { fg = "#98d3cb"; }; # Teal
    };
    input = {
      border = { fg = "#367bbf"; }; title = { };
      value = { fg = "#6C7E96"; }; selected = { bg = "#000000"; };
    };
    select = {
      border = { fg = "#98d3cb"; }; active = { fg = "#98d3cb"; }; inactive = { fg = "#6C7E96"; };
    };
    tasks = {
      border = { fg = "#367bbf"; }; title = { }; hovered = { fg = "#367bbf"; underline = true; };
    };
    which = {
      cols = 3; mask = { bg = "#000000"; }; cand = { fg = "#98d3cb"; };
      rest = { fg = "#6C7E96"; }; desc = { fg = "#367bbf"; };
      separator = "  "; separator_style = { fg = "#3D3D3D"; };
    };
    notify = {
      title_info = { fg = "#367bbf"; }; title_warn = { fg = "#FFC44E"; }; title_error = { fg = "#CF4F88"; };
      icon_info = "ZE "; icon_warn = "ZE "; icon_error = "ZE ";
    };
    help = {
      on = { fg = "#367bbf"; }; exec = { fg = "#98d3cb"; }; desc = { fg = "#6C7E96"; };
      hovered = { bg = "#000000"; bold = true; }; footer = { fg = "#6C7E96"; bg = "#000000"; };
    };
  };

  keymap = {
    mgr.prepend_keymap = [
      {
        on = [ "g" "s" ];
        run = "plugin save-file --args=overwrite";
        desc = "Save (Default/Overwrite)";
      }
      {
        on = [ "g" "z" ];
        run = "plugin save-file --args=input";
        desc = "Save as new file (Input)";
      }
      { on = [ "<C-s>" ]; run = "quit"; desc = "Confirm selection (Save)"; }
      { on = [ "g" "r" ]; run = ''shell -- ya emit cd "$(git rev-parse --show-toplevel)"''; desc = "Go to git root"; }
      { run = "close"; on = [ "<Esc>" ]; }
      { run = "close"; on = [ "<C-q>" ]; }
      { run = "yank --cut"; on = [ "d" ]; }
      { run = "remove --force"; on = [ "D" ]; }
      { run = "remove --permanently"; on = [ "X" ]; }
      { on = [ "f" ]; run = ''shell "$SHELL" --block''; desc = "Open $SHELL here"; }
      { run = "plugin smart-paste"; on = [ "p" ]; desc = "Smart paste"; }
      { run = "plugin paste-to-select"; on = [ "g" "p" ]; desc = "Reveal file from clipboard"; }
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

      local function main_logic()
        log("Plugin started (main_logic).")
        local args = {}
        
        log("Checking state type...")
        if state == nil then
            log("State is nil")
        else
            log("State type: " .. type(state))
        end

        if state and type(state) == "table" and state.args then
             log("Extracting args from state.args")
             args = state.args
        else
             log("Checking varargs...")
             local va = { ... }
             if #va > 0 then
                log("Varargs found: " .. #va)
                args = { state, ... }
             else
                log("No args found via varargs")
             end
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
          if not filename or filename == "" then 
              log("Empty filename, aborting save")
              return 
          end
          local full_path = filename
          if string.sub(filename, 1, 1) ~= "/" then
             full_path = tostring(cwd) .. "/" .. filename
          end
          
          log("Full path: " .. full_path)
          local out_file = io.open(output_path, "w")
          if out_file then
            out_file:write(full_path)
            out_file:close()
          else
            log("Failed to write to portal output")
            ya.notify({ title = "Save File", content = "Failed to write to portal output", timeout = 5.0, level = "error" })
            return
          end
          
          local f = io.open(full_path, "a")
          if f then f:close() end
          
          log("Quitting yazi...")
          ya.manager_emit("quit", { "--no-confirm" })
        end

        if mode == "input" then
          log("Requesting input...")
          local value, event = ya.input({
            title = "Save as (New File):", 
            value = suggested or "", 
            pos = { "top-center", y = 3, w = 40 }
          })
          log("Input result: " .. tostring(value))
          if value then save(value) end
        elseif mode == "overwrite" then
          if suggested and suggested ~= "" then
             log("Auto-saving suggested: " .. suggested)
             save(suggested)
          else
             local hovered = cx.active.current.hovered
             if hovered then
               log("Saving hovered: " .. tostring(hovered.name))
               save(tostring(hovered.name))
             else
               log("No hovered, requesting input")
               local value, event = ya.input({
                  title = "Save as:", 
                  value = "", 
                  pos = { "top-center", y = 3, w = 40 }
               })
               log("Input result: " .. tostring(value))
               if value then save(value) end
             end
          end
        else
          log("Unknown mode: " .. tostring(mode))
        end
      end

      -- Run with error handling
      local status, err = xpcall(main_logic, debug.traceback)
      if not status then
         log("CRITICAL ERROR: " .. tostring(err))
         ya.notify({ title = "Plugin Error", content = tostring(err), timeout = 10.0, level = "error" })
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
