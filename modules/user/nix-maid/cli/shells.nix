{
  inputs,
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  # --- Config Sources ---
  shellFiles = ../../../../files/shell;
  kittyConf = ../../../../files/kitty;
  tmuxConfDir = ../../../../files/tmux;
  dircolorsConfig = "${inputs.self}/files/shell/dircolors/dircolors";

  # --- Inputrc ---
  inputrc = ''
    set bell-style                 none
    set bind-tty-special-chars     on
    set completion-ignore-case     on
    set completion-map-case        on
    set completion-query-items     200
    set echo-control-characters    off
    set enable-keypad              on
    set enable-meta-key            on
    set history-preserve-point     off
    set history-size               1000
    set horizontal-scroll-mode     off
    set input-meta                 on
    set output-meta                on
    set convert-meta               off
    set mark-directories           on
    set mark-modified-lines        off
    set mark-symlinked-directories on
    set match-hidden-files         off
    set meta-flag                  on
    set page-completions           off
    set show-all-if-ambiguous      on
    set show-all-if-unmodified     on
    set skip-completed-text        on
    set visible-stats              on
    set colored-stats              on
    set completion-prefix-display-length 3

    $if mode=vi
      set keymap vi-insert
      "gg": beginning-of-history
      "G": end-of-history
      "j": history-search-forward
      "k": history-search-backward
      set keymap vi-insert
      "kj": vi-movement-mode
      "\C-w": backward-kill-word
      "\C-l": clear-screen
      # auto-complete from the history
      "\C-p": history-search-backward
      "\C-n": history-search-forward
    $endif

    "\C-w": backward-kill-word
    "\ew": copy-backward-word
    "\C-p": history-search-backward
    "\C-n": history-search-forward
    "\e[B": history-search-forward
    "\e[A": history-search-backward
    "\C-x\C-i": menu-complete
    "\C-x\C-o": menu-complete-backward
    "\C-x\C-r": re-read-init-file
    "\C-u": kill-whole-line
    "\C-\M-w": unix-word-rubout
    "\ei": tab-insert
  '';

  # --- Aliae Config ---
  aliaeConfig = import "${inputs.self}/lib/aliae.nix" {
    inherit lib pkgs;
    homeDir = config.users.users.neg.home;
  };

  # --- ZSH Config Generator ---
  # Git fsmonitor auto-enable for large repos (ported from legacy Salt 05-git.zsh)
  zshenvExtras = ''
    # Auto-enable git core.fsmonitor for large repositories (>50k files via index size proxy)
    __git_fsmonitor_threshold=$((5 * 1024 * 1024))
    __git_fsmonitor_checked=()

    _git_fsmonitor_auto_enable() {
      local git_root
      git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return
      [[ " ''${__git_fsmonitor_checked[@]} " =~ " $git_root " ]] && return
      __git_fsmonitor_checked+=("$git_root")
      local index_path="$git_root/.git/index"
      [[ -f "$index_path" ]] || return
      local index_size
      index_size=$(stat -c%s "$index_path" 2>/dev/null) || return
      if (( index_size > __git_fsmonitor_threshold )); then
        git config --local core.fsmonitor true
        echo -e "\033[33m[git]\033[0m enabled core.fsmonitor for \033[36m''${git_root##*/}\033[0m ($((index_size / 1024))K index)"
      fi
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook chpwd _git_fsmonitor_auto_enable
  '';
  zshConfigSource = pkgs.runCommandLocal "neg-zsh-config" { } ''
    mkdir -p "$out"
    cp -R ${shellFiles}/zsh/. "$out"/
    chmod -R u+w "$out"
    sed -i "s|@zinit@|${pkgs.zinit}|g" "$out/.zshrc"
    sed -i "s|@native-syntax@|${pkgs.neg.zsh-native-syntax}|g" "$out/.zshrc"
    cat > "$out/.zshenv" <<'EOF'
    # shellcheck disable=SC1090
    skip_global_compinit=1
    # Hardcoded path for profile session vars (standard location)
    session_vars="$HOME/.nix-profile/etc/profile.d/session-vars.sh"
    if [ -r "$session_vars" ]; then
      . "$session_vars"
    elif [ -r "/etc/profiles/per-user/$USER/etc/profile.d/session-vars.sh" ]; then
      . "/etc/profiles/per-user/$USER/etc/profile.d/session-vars.sh"
    fi
    export WORDCHARS='*/?_-.[]~&;!#$%^(){}<>~` '
    export KEYTIMEOUT=10
    export REPORTTIME=60
    export ESCDELAY=1
    ${zshenvExtras}
    EOF
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
      # Pre-establish shell config dirs with correct ownership so that
      # nix-maid's later symlink-layer (into the nix store) doesn't trip
      # systemd-tmpfiles' unsafe-path-transition check (systemd >=252).
      systemd.tmpfiles.rules = [
        "d /home/neg/.config/zsh 0755 neg neg -"
        "d /home/neg/.config/zsh-native-syntax 0755 neg neg -"
      ];

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
          if config.features.cli.broot.enable then
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
        # Terminals
        pkgs.kitty # GPU-accelerated terminal with ligatures and image support

        # Shells
        pkgs.tmux # Terminal multiplexer for session management
        pkgs.oh-my-posh # Cross-shell prompt theme engine
        pkgs.zinit # Zsh plugin manager (zi)

        # Tools needed for kitty-panel
        pkgs.btop # Resource monitor (CPU, memory, disks, network)
        pkgs.cava # Console audio visualizer
        pkgs.peaclock # Customizable clock for terminal
        pkgs.curl # HTTP client for weather fetching
        pkgs.mtr # Network diagnostic tool
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

    (n.mkHomeFiles {
      # --- General Shell Configs ---
      ".config/inputrc".text = inputrc;
      ".config/aliae/config.yaml".text = aliaeConfig;
      ".config/dircolors/dircolors".source = dircolorsConfig;
      ".config/zsh".source = zshConfigSource;
      ".config/bash/oh-my-posh.bash".source = "${shellFiles}/bash/oh-my-posh.bash";
      ".config/f-sy-h".source = "${shellFiles}/f-sy-h";
      ".config/zsh-native-syntax".source = "${shellFiles}/zsh-native-syntax";

      # --- Terminal & Specific Shell Configs ---

      # Kitty Config
      ".config/kitty".source = kittyConf;

      # Tmux Config
      ".config/tmux".source = tmuxConfDir;

    })
  ];
}
