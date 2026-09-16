{
  pkgs,
  lib,
  config,

  neg,
  ...
}:
let
  cfg = config.features.cli.yazi;
  tomlFormat = pkgs.formats.toml { };
  # ЙЦУКЕН table + generators (lib/ru-keys.nix via specialArgs.neg) — the only
  # source for Russian-layout duplicate binds in this file.
  ruKeys = neg.ruKeys;

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

  # Positional constructors for the keymap below: nixfmt keeps a three-name
  # `inherit` on one line, so each record costs one line instead of 6-8.
  yaziBind = on: run: desc: { inherit on run desc; };
  yaziBindNoDesc = on: run: { inherit on run; };
  keymap = {
    mgr.prepend_keymap = [
      (yaziBind [ "g" "s" ] "plugin save-file --args=overwrite" "Save (Default/Overwrite)")
      (yaziBind [ "g" "z" ] "plugin save-file --args=input" "Save as new file (Input)")
      (yaziBind [ "<C-s>" ] "quit" "Confirm selection (Save)")
      (yaziBind [ "g" "r" ] ''shell -- ya emit cd "$(git rev-parse --show-toplevel)"'' "Go to git root")
      (yaziBindNoDesc [ "<Esc>" ] "close")
      (yaziBindNoDesc [ "<C-q>" ] "close")
      (yaziBindNoDesc [ "d" ] "yank --cut")
      (yaziBindNoDesc [ "D" ] "remove --force")
      (yaziBindNoDesc [ "X" ] "remove --permanently")
      (yaziBind [ "f" ] ''shell "$SHELL" --block'' "Open $SHELL here")
      (yaziBind [ "p" ] "plugin smart-paste" "Smart paste")
      (yaziBind [ "g" "p" ] "plugin paste-to-select" "Reveal file from clipboard")
      # --- Emacs-style navigation (additive; vi keys still work) ---
      # Ctrl binds are layout-independent, so no RU duplicates are needed.
      (yaziBind [ "<C-n>" ] "arrow next" "Down (emacs C-n)")
      (yaziBind [ "<C-p>" ] "arrow prev" "Up (emacs C-p)")
      (yaziBind [ "<C-b>" ] "leave" "Parent directory (emacs C-b)")
      (yaziBind [ "<C-f>" ] "enter" "Open entry (emacs C-f)")
      (yaziBind [ "<C-a>" ] "arrow top" "First entry (emacs C-a)")
      (yaziBind [ "<C-e>" ] "arrow bottom" "Last entry (emacs C-e)")
      # --- Russian layout duplicates (ЙЦУКЕН) -------------------------------------
      # yazi matches keys by the produced char; latin-letter binds break under the
      # ru layout. Lowercase Cyrillic only (uppercase implies SHIFT, which the RU
      # layout reports differently). All duplicates are GENERATED from
      # lib/ru-keys.nix (single source of truth) — do not hand-edit the chars.
      # Table: docs/howto/hotkeys-ru-layout.md
      (yaziBindNoDesc (ruKeys.mkRuKeys [ "j" ]) "arrow next")
      (yaziBindNoDesc (ruKeys.mkRuKeys [ "k" ]) "arrow prev")
      (yaziBindNoDesc (ruKeys.mkRuKeys [ "h" ]) "leave")
      (yaziBindNoDesc (ruKeys.mkRuKeys [ "l" ]) "enter")
      (yaziBindNoDesc (ruKeys.mkRuKeys [
        "g"
        "g"
      ]) "arrow top")
      (yaziBindNoDesc (ruKeys.mkRuKeys [ "d" ]) "yank --cut")
      (yaziBindNoDesc (ruKeys.mkRuKeys [
        "g"
        "s"
      ]) "plugin save-file --args=overwrite")
      (yaziBindNoDesc (ruKeys.mkRuKeys [
        "g"
        "z"
      ]) "plugin save-file --args=input")
      (yaziBindNoDesc (ruKeys.mkRuKeys [
        "g"
        "r"
      ]) ''shell -- ya emit cd "$(git rev-parse --show-toplevel)"'')
      (yaziBindNoDesc (ruKeys.mkRuKeys [ "p" ]) "plugin smart-paste")
      (yaziBindNoDesc (ruKeys.mkRuKeys [
        "g"
        "p"
      ]) "plugin paste-to-select")
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

  save-file-plugin = config.lib.neg.readFile "files/yazi/plugins/save-file.yazi/main.lua";

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
    (neg.mkHomeFiles {
      ".config/yazi/yazi.toml".source = tomlFormat.generate "yazi.toml" settings;
      ".config/yazi/theme.toml".source = tomlFormat.generate "theme.toml" theme;
      ".config/yazi/keymap.toml".source = tomlFormat.generate "keymap.toml" keymap;
      ".config/yazi/plugins/smart-paste.yazi".source = "${yazi-plugins}/smart-paste.yazi";
      ".config/yazi/plugins/paste-to-select.yazi/main.lua".text = paste-to-select-plugin;
      ".config/yazi/plugins/save-file.yazi/main.lua".text = save-file-plugin;
    })
  ]
)
