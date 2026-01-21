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
  nuConfDir = ../../../../files/nushell;
  tmuxConfDir = ../../../../files/tmux;
  ompConfig = ../../../../files/shell/zsh/neg.omp.json;
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
  zshenvExtras = "";
  zshConfigSource = pkgs.runCommandLocal "neg-zsh-config" { } ''
    mkdir -p "$out"
    cp -R ${shellFiles}/zsh/. "$out"/
    chmod -R u+w "$out"
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

  shellAliases = { };
in
{
  config = lib.mkMerge [
    {
      # Ensure Config Dirs exist for shells
      systemd.tmpfiles.rules = [
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
        pkgs.nushell # Modern shell with structured data pipelines
        pkgs.tmux # Terminal multiplexer for session management
        pkgs.oh-my-posh # Cross-shell prompt theme engine

        # Tools needed for kitty-panel
        pkgs.btop # Resource monitor (CPU, memory, disks, network)
        pkgs.cava # Console audio visualizer
        pkgs.peaclock # Customizable clock for terminal
        pkgs.curl # HTTP client for weather fetching
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

      # --- Terminal & Specific Shell Configs ---

      # Kitty Config
      ".config/kitty".source = n.linkImpure kittyConf;

      # Tmux Config
      ".config/tmux".source = n.linkImpure tmuxConfDir;

      # Nushell Config
      ".config/nushell/aliases.nu".source = n.linkImpure (nuConfDir + /aliases.nu);
      ".config/nushell/git.nu".source = n.linkImpure (nuConfDir + /git.nu);
      ".config/nushell/broot.nu".source = n.linkImpure (nuConfDir + /broot.nu);
      ".config/nushell/git-completion.nu".source = n.linkImpure (nuConfDir + /git-completion.nu);
      # We construct config/env manually to inject dynamic content if needed,
      # or just source them.
      ".config/nushell/config.nu".source = n.linkImpure (nuConfDir + /config.nu);

      # For env.nu, we append the oh-my-posh init
      ".config/nushell/env.nu".text = builtins.readFile "${nuConfDir}/env.nu" + ''


        # -- Generated by NixOS --
        # Oh-My-Posh Init (Nushell)
        $env.OMP_CONFIG = "${n.linkImpure ompConfig}"
        oh-my-posh init nu --config $env.OMP_CONFIG --print | save -f ~/.cache/oh-my-posh-init.nu
        source ~/.cache/oh-my-posh-init.nu
        $env.PROMPT_COMMAND_RIGHT = ""
      '';
    })
  ];
}
