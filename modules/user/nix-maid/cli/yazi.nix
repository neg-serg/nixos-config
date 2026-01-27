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
      
      # Unified execution: Always use --chooser-file so 'open' action selects the file.
      # We also track CWD if needed, though strictly strictly mostly for debugging or restoring state if we weren't quitting.
      ${pkgs.yazi}/bin/yazi --chooser-file='$OUTPUT_PATH' --cwd-file='$CWD_FILE'
      
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
    local function entry(state)
      local mode = state.args[1]
      local cwd = cx.active.current.cwd

      local function save(filename)
        if not filename or filename == "" then return end
        local full_path = filename
        if string.sub(filename, 1, 1) ~= "/" then
           full_path = tostring(cwd) .. "/" .. filename
        end
        
        -- Touch the file to ensure it exists
        local f = io.open(full_path, "a")
        if f then f:close() end
        
        -- Reveal and Open. Since we are in chooser-file mode, 'open' selects the file and exits.
        ya.manager_emit("reveal", { full_path })
        ya.manager_emit("open", { hovered = true })
      end

      if mode == "input" then
        ya.input({
          title = "Save as (New File):", value = "", position = { "top-center", y = 3, w = 40 }
        }):then_call(function(value, event) if value then save(value) end end)
      elseif mode == "overwrite" then
           local hovered = cx.active.current.hovered
           if hovered then
             save(tostring(hovered.name))
           else
             ya.input({
                title = "Save as:", value = "", position = { "top-center", y = 3, w = 40 }
             }):then_call(function(value, event) if value then save(value) end end)
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
