{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
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
  aliaeConfig = import "${inputs.self}/lib/aliae.nix" {inherit lib pkgs;};
  dircolorsConfig = "${inputs.self}/home/files/shell/dircolors/dircolors";
  shellAliases = {}; # Placeholder, assuming it's defined elsewhere or will be added.
in {
  users.users.neg.maid.file.home = {
    ".inputrc".text = inputrc;

    ".config/aliae/config.yaml".text = aliaeConfig;

    ".config/dircolors/dircolors" = {
      source = dircolorsConfig;
    };
  };

  # --- Interactive Shell Config (Bash) ---
  programs.bash = {
    enable = true;
    inherit shellAliases;
    interactiveShellInit =
      ''
        ${pkgs.nix-your-shell}/bin/nix-your-shell bash | source /dev/stdin

        if [[ -f ~/.config/dircolors/dircolors ]]; then
          eval "$(${pkgs.coreutils}/bin/dircolors -b ~/.config/dircolors/dircolors)"
        fi
      ''
      + (
        if config.features.cli.broot.enable
        then ''
          source ~/.config/broot/launcher/bash/br
        ''
        else ""
      )
      + ''
      '';
  };
}
