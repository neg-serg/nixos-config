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

  # --- Kitty key.conf: generated Russian-layout duplicates ---
  # ЙЦУКЕН duplicate binds are GENERATED from lib/ru-keys.nix (single source of
  # truth). Each entry mirrors a latin bind from files/kitty/key.conf; the
  # generator derives the literal Cyrillic chars, so typos are impossible.
  # Table: docs/howto/hotkeys-ru-layout.md
  kittyRuBinds = [
    {
      mod = "ctrl+shift";
      keys = [ "v" ];
      action = "paste_from_clipboard";
    }
    {
      mod = "ctrl+shift";
      keys = [ "z" ];
      action = "scroll_to_prompt -1";
    }
    {
      mod = "ctrl+shift";
      keys = [ "x" ];
      action = "scroll_to_prompt 1";
    }
    {
      mod = "ctrl+shift";
      keys = [ "q" ];
      action = "close_tab";
    }
    {
      mod = "ctrl+shift";
      keys = [ "w" ];
      action = "close_window";
    }
    {
      mod = "ctrl+shift";
      keys = [ "," ];
      action = "move_tab_backward";
    }
    {
      mod = "ctrl+shift";
      keys = [ "." ];
      action = "move_tab_forward";
    }
    {
      mod = "ctrl+shift";
      keys = [ "b" ];
      action = "move_window_backward";
    }
    {
      mod = "ctrl+shift";
      keys = [ "f" ];
      action = "move_window_forward";
    }
    {
      mod = "ctrl+shift";
      keys = [ "`" ];
      action = "move_window_to_top";
    }
    {
      mod = "ctrl+shift";
      keys = [ "]" ];
      action = "next_window";
    }
    {
      mod = "ctrl+shift";
      keys = [ "[" ];
      action = "previous_window";
    }
    {
      mod = "ctrl+shift";
      keys = [ "l" ];
      action = "next_layout";
    }
    {
      mod = "ctrl+shift";
      keys = [ "u" ];
      action = "kitten unicode_input";
    }
    {
      mod = "ctrl+shift";
      keys = [ "e" ];
      action = "neghints --type=url";
    }
    {
      mod = "ctrl+shift";
      keys = [ "h" ];
      action = "kitty_scrollback_nvim";
    }
    {
      mod = "ctrl+shift";
      keys = [ "o" ];
      action = "kitty_scrollback_nvim --env KSB_OPEN_GF=1";
    }
    {
      mod = "ctrl+shift+alt";
      keys = [ "t" ];
      action = "set_tab_title";
    }
    {
      mod = "ctrl+shift";
      keys = [ "t" ];
      action = "new_tab";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "s"
        "f"
      ];
      action = "neghints --program @";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "s"
        "w"
      ];
      action = "neghints --type word --program @";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "s"
        "l"
      ];
      action = "neghints --type line --program @";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "s"
        "p"
      ];
      action = "neghints --type path --program @";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "s"
        "h"
      ];
      action = "neghints --type hash --program @";
    }
    {
      mod = "Ctrl";
      keys = [
        "s"
        "w"
      ];
      action = "neghints --type word --program -";
    }
    {
      mod = "Ctrl";
      keys = [
        "s"
        "l"
      ];
      action = "neghints --type line --program -";
    }
    {
      mod = "Ctrl";
      keys = [
        "s"
        "p"
      ];
      action = "neghints --type path --program -";
    }
    {
      mod = "Ctrl";
      keys = [
        "s"
        "h"
      ];
      action = "neghints --type hash --program -";
    }
    {
      mod = "Ctrl+alt";
      keys = [ "s" ];
      action = "kitty_scrollback_nvim --config screen";
    }
    {
      mod = "alt";
      keys = [ "n" ];
      action = "new_tab";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "r"
        "r"
      ];
      action = "load_config_file";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "r"
        "e"
      ];
      action = "debug_config";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "r"
        "w"
      ];
      action = "start_resizing_window";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "a"
        "1"
      ];
      action = "set_background_opacity 1";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "a"
        "d"
      ];
      action = "set_background_opacity default";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "a"
        "l"
      ];
      action = "set_background_opacity -0.1";
    }
    {
      mod = "ctrl+shift";
      keys = [
        "a"
        "m"
      ];
      action = "set_background_opacity +0.1";
    }
    # Emacs-style scrollback navigation (files/kitty/key.conf).
    # Uses Ctrl+Alt (not Ctrl+Shift) so it does not collide with the kitty_mod
    # (Ctrl+Shift) window-move / window-focus binds on b/f/p.
    {
      mod = "ctrl+alt";
      keys = [ "n" ];
      action = "scroll_line_down";
    }
    {
      mod = "ctrl+alt";
      keys = [ "p" ];
      action = "scroll_line_up";
    }
    {
      mod = "ctrl+alt";
      keys = [ "f" ];
      action = "scroll_page_down";
    }
    {
      mod = "ctrl+alt";
      keys = [ "b" ];
      action = "scroll_page_up";
    }
    {
      mod = "alt";
      keys = [ "v" ];
      action = "scroll_page_up";
    }
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
      ".config/zsh-native-syntax".source = "${shellFiles}/zsh-native-syntax";
      # --- Terminal & Specific Shell Configs ---
      # kitty dir deployed per-file: key.conf is GENERATED (latin binds from
      # files/kitty/key.conf + RU duplicates from lib/ru-keys.nix), the rest is
      # deployed as-is from files/kitty/.
      ".config/kitty/key.conf".text = kittyKeyConf;
      ".config/kitty/font.conf".source = "${kittyConf}/font.conf";

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
