{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # --- Config Sources ---
  shellFiles = config.lib.neg.path "files/shell";
  kittyConf = config.lib.neg.path "files/kitty";
  irisConfig = config.lib.neg.path "files/iris";
  dircolorsConfig = config.lib.neg.path "files/shell/dircolors/dircolors";

  # Positional constructor for the table below: nixfmt keeps a three-name
  # `inherit` on one line, so each record costs one line instead of five.
  kittyBind = mod: keys: action: { inherit mod keys action; };

  # --- Kitty key.conf: generated Russian-layout duplicates ---
  # ЙЦУКЕН duplicate binds are GENERATED from lib/ru-keys.nix (single source of
  # truth). Each entry mirrors a latin bind from files/kitty/key.conf; the
  # generator derives the literal Cyrillic chars, so typos are impossible.
  # Table: docs/howto/hotkeys-ru-layout.md
  kittyRuBinds = [
    (kittyBind "ctrl+shift" [ "v" ] "paste_from_clipboard")
    (kittyBind "ctrl+shift" [ "z" ] "scroll_to_prompt -1")
    (kittyBind "ctrl+shift" [ "x" ] "scroll_to_prompt 1")
    (kittyBind "ctrl+shift" [ "q" ] "close_tab")
    (kittyBind "ctrl+shift" [ "w" ] "close_window")
    (kittyBind "ctrl+shift" [ "," ] "move_tab_backward")
    (kittyBind "ctrl+shift" [ "." ] "move_tab_forward")
    (kittyBind "ctrl+shift" [ "b" ] "move_window_backward")
    (kittyBind "ctrl+shift" [ "f" ] "move_window_forward")
    (kittyBind "ctrl+shift" [ "`" ] "move_window_to_top")
    (kittyBind "ctrl+shift" [ "]" ] "next_window")
    (kittyBind "ctrl+shift" [ "[" ] "previous_window")
    (kittyBind "ctrl+shift" [ "l" ] "next_layout")
    (kittyBind "ctrl+shift" [ "u" ] "kitten unicode_input")
    (kittyBind "ctrl+shift" [ "e" ] "neghints --type=url")
    (kittyBind "ctrl+shift" [ "h" ] "kitty_scrollback_nvim")
    (kittyBind "ctrl+shift" [ "o" ] "kitty_scrollback_nvim --env KSB_OPEN_GF=1")
    (kittyBind "ctrl+shift+alt" [ "t" ] "set_tab_title")
    (kittyBind "ctrl+shift" [ "t" ] "new_tab")
    (kittyBind "ctrl+shift" [ "s" "f" ] "neghints --program @")
    (kittyBind "ctrl+shift" [ "s" "w" ] "neghints --type word --program @")
    (kittyBind "ctrl+shift" [ "s" "l" ] "neghints --type line --program @")
    (kittyBind "ctrl+shift" [ "s" "p" ] "neghints --type path --program @")
    (kittyBind "ctrl+shift" [ "s" "h" ] "neghints --type hash --program @")
    (kittyBind "Ctrl" [ "s" "w" ] "neghints --type word --program -")
    (kittyBind "Ctrl" [ "s" "l" ] "neghints --type line --program -")
    (kittyBind "Ctrl" [ "s" "p" ] "neghints --type path --program -")
    (kittyBind "Ctrl" [ "s" "h" ] "neghints --type hash --program -")
    (kittyBind "Ctrl+alt" [ "s" ] "kitty_scrollback_nvim --config screen")
    (kittyBind "alt" [ "n" ] "new_tab")
    (kittyBind "ctrl+shift" [ "r" "r" ] "load_config_file")
    (kittyBind "ctrl+shift" [ "r" "e" ] "debug_config")
    (kittyBind "ctrl+shift" [ "r" "w" ] "start_resizing_window")
    (kittyBind "ctrl+shift" [ "a" "1" ] "set_background_opacity 1")
    (kittyBind "ctrl+shift" [ "a" "d" ] "set_background_opacity default")
    (kittyBind "ctrl+shift" [ "a" "l" ] "set_background_opacity -0.1")
    (kittyBind "ctrl+shift" [ "a" "m" ] "set_background_opacity +0.1")
    # Emacs-style scrollback navigation (files/kitty/key.conf).
    # Uses Ctrl+Alt (not Ctrl+Shift) so it does not collide with the kitty_mod
    # (Ctrl+Shift) window-move / window-focus binds on b/f/p.
    (kittyBind "ctrl+alt" [ "n" ] "scroll_line_down")
    (kittyBind "ctrl+alt" [ "p" ] "scroll_line_up")
    (kittyBind "ctrl+alt" [ "f" ] "scroll_page_down")
    (kittyBind "ctrl+alt" [ "b" ] "scroll_page_up")
    (kittyBind "alt" [ "v" ] "scroll_page_up")
  ];

  kittyRuBlock = ''
    # --- Russian layout duplicates (ЙЦУКЕН) -----------------------------------------
    # GENERATED from lib/ru-keys.nix — do not edit by hand. Bind data lives in
    # modules/user/nix-maid/cli/shells.nix (kittyRuBinds).
    # kitty matches shortcuts by the produced char of the ACTIVE layout, so under
    # the ru layout every latin-letter shortcut breaks. These duplicates bind the
    # same actions to the literal Cyrillic chars produced by the same physical
    # keys (keysym NAMES are unusable: kitty resolves them via libxkbcommon,
    # which is not loadable on this system).
    # Table: docs/howto/hotkeys-ru-layout.md
  ''
  + builtins.concatStringsSep "\n" (neg.ruKeys.mkKittyLines kittyRuBinds)
  + "\n";

  # key.conf = latin binds (files/kitty/key.conf) + generated RU duplicates.
  kittyKeyConf = builtins.readFile "${kittyConf}/key.conf" + "\n" + kittyRuBlock;

  # --- Inputrc ---
  inputrc = builtins.readFile (config.lib.neg.path "files/cli/inputrc");

  # --- Aliae Config ---
  aliaeConfig = import (config.lib.neg.path "lib/aliae.nix") {
    inherit lib pkgs;
    homeDir = config.users.users.neg.home;
  };

  # --- ZSH Config Generator ---
  # Git fsmonitor auto-enable for large repos (ported from legacy Salt 05-git.zsh)
  zshenvExtras = builtins.readFile (config.lib.neg.path "files/shell/zshenv-extras.zsh");
  zshConfigSource = pkgs.runCommandLocal "neg-zsh-config" { } (
    builtins.replaceStrings
      [ "@SHELLFILES@" "@ZINIT@" "@SYNTAX@" "@ZSHENVEXTRAS@" ]
      [ "${shellFiles}" "${pkgs.zinit}" "${pkgs.neg.zsh-native-syntax}" "${zshenvExtras}" ]
      (builtins.readFile ./zsh-config-source.sh)
  );

  # --- zsh-native-syntax theme, derived from the f-sy-h theme ---
  # files/shell/f-sy-h/neg.ini is the single source for both themes: the Rust
  # engine reads ~/.config/zsh-native-syntax/theme.ini, which differs from
  # neg.ini only in the [paths] values (plus path-tilde) and the extra
  # [param-expansion] section. Materialised in the Nix store so ~/.config stays
  # the same read-only symlink it was when theme.ini was a second checked-in copy.
  zshNativeThemeText = builtins.toFile "theme.ini" (
    lib.replaceStrings
      [
        "path          = none"
        "pathseparator = 4"
        "path-to-dir   = 248,underline"
        "history-expansion    = blue,bold"
      ]
      [
        "path          = white"
        "pathseparator = blue,bold"
        "path-to-dir   = white\npath-tilde    = green,bold"
        "history-expansion    = blue,bold\n\n[param-expansion]\nparamvar     = 63\nparamoper    = 141\nparamdefault = 249"
      ]
      (builtins.readFile (shellFiles + "/f-sy-h/neg.ini"))
  );

  zshNativeSyntaxTheme = pkgs.runCommandLocal "neg-zsh-native-syntax" { } ''
    mkdir -p $out
    cp ${zshNativeThemeText} $out/theme.ini
  '';

  # Kitty Scrollback Path (for session variable)
  nixKsbPath = "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";

  shellAliases = {
    ping = "mtr";
  };
in
{
  config = lib.mkMerge [
    {
      # NOTE: nix-maid creates symlinks to the nix store at these paths via
      # mkHomeFiles below.  Do NOT add systemd-tmpfiles 'd' rules here — they
      # will fail on every subsequent boot because nix-maid's symlinks persist
      # and tmpfiles cannot create directories on top of existing symlinks.

      # --- Interactive Shell Config (Bash) ---
      programs.bash = {
        enable = true;
        inherit shellAliases;
        interactiveShellInit = ''
          ${pkgs.nix-your-shell}/bin/nix-your-shell bash | source /dev/stdin # `nix` and `nix-shell` wrapper for shells other than `bash`

          if [[ -f ~/.config/dircolors/dircolors ]]; then
            eval "$(${pkgs.coreutils}/bin/dircolors -b ~/.config/dircolors/dircolors)" # GNU Core Utilities
          fi
        ''
        + (
          if config.lib.neg.enabled "cli.broot" then
            ''
              eval "$(${pkgs.broot}/bin/broot --print-shell-function bash)"
            ''
          else
            ""
        )
        + ''
          source ~/.config/bash/oh-my-posh.bash
        '';
      };

      environment.systemPackages = [
        pkgs.btop # Resource monitor (CPU, memory, disks, network)
        pkgs.cava # Console audio visualizer
        pkgs.kitty # GPU-accelerated terminal with ligatures and image support
        pkgs.mtr # Network diagnostic tool
        pkgs.oh-my-posh # Cross-shell prompt theme engine
        pkgs.zinit # Zsh plugin manager (zi)
      ];

      environment.sessionVariables = {
        ZDOTDIR = "$HOME/.config/zsh";
        TERMINAL = "kitty";
        MANWIDTH = "80";
        GREP_COLOR = "37;45";
        GREP_COLORS = "ms=0;32:mc=1;33:sl=:cx=:fn=1;32:ln=1;36:bn=36:se=1;30";
        KITTY_KSB_NIX_PATH = nixKsbPath;
      };
    }

    (neg.mkHomeFiles {
      # --- General Shell Configs ---
      ".config/inputrc".text = inputrc;
      ".config/aliae/config.yaml".text = aliaeConfig;
      ".config/dircolors/dircolors".source = dircolorsConfig;
      ".config/zsh".source = zshConfigSource;
      ".config/iris/config.toml".source = "${irisConfig}/config.toml";
      ".config/iris/theme.toml".source = "${irisConfig}/theme.toml";
      ".config/bash/oh-my-posh.bash".source = "${shellFiles}/bash/oh-my-posh.bash";
      ".config/f-sy-h".source = "${shellFiles}/f-sy-h";
      ".config/zsh-native-syntax".source = zshNativeSyntaxTheme;
      # --- Terminal & Specific Shell Configs ---
      # kitty dir deployed per-file: key.conf is GENERATED (latin binds from
      # files/kitty/key.conf + RU duplicates from lib/ru-keys.nix), the rest is
      # deployed as-is from files/kitty/.
      ".config/kitty/key.conf".text = kittyKeyConf;
      ".config/kitty/font.conf".source = "${kittyConf}/font.conf";
      ".config/kitty/font_zoom.py".source = "${kittyConf}/font_zoom.py";

      ".config/kitty/kitty.conf".source = "${kittyConf}/kitty.conf";
      ".config/kitty/mouse.conf".source = "${kittyConf}/mouse.conf";
      ".config/kitty/range_select.py".source = "${kittyConf}/range_select.py";
      ".config/kitty/scroll_mark.py".source = "${kittyConf}/scroll_mark.py";
      ".config/kitty/search.py".source = "${kittyConf}/search.py";
      ".config/kitty/tab_bar.py".source = "${kittyConf}/tab_bar.py";
      ".config/kitty/tab.conf".source = "${kittyConf}/tab.conf";
      ".config/kitty/theme.conf".source = "${kittyConf}/theme.conf";
    })
  ];
}
