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

  # --- Shell Config Sources ---
  shellFiles = ../../../home/files/shell;
  zshenvExtras = "";

  # Generate ZSH config with injected zshenv
  zshConfigSource = pkgs.runCommandLocal "neg-zsh-config" {} ''
    mkdir -p "$out"
    cp -R ${shellFiles}/zsh/. "$out"/
    chmod -R u+w "$out"
    cat > "$out/.zshenv" <<'EOF'
    # shellcheck disable=SC1090
    skip_global_compinit=1
    # Hardcoded path for Home Manager session vars (standard location)
    hm_session_vars="$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    if [ -r "$hm_session_vars" ]; then
      . "$hm_session_vars"
    elif [ -r "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
      . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
    fi
    export WORDCHARS='*/?_-.[]~&;!#$%^(){}<>~` '
    export KEYTIMEOUT=10
    export REPORTTIME=60
    export ESCDELAY=1
    ${zshenvExtras}
    EOF
  '';

  # PowerShell Profile
  pwshProfile = ''
    # Aliae integration for PowerShell (pwsh)
    try {
      $cfg = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'aliae/config.yaml' } else { Join-Path $HOME '.config/aliae/config.yaml' }
      if (Get-Command aliae -ErrorAction SilentlyContinue) {
        # Print init script and invoke it so aliases/functions load
        $init = aliae init pwsh --config $cfg --print | Out-String
        if ($init) { Invoke-Expression $init }
      }
    } catch {}

    # Fallback aliases/functions to ensure parity with other shells
    function Set-IfCmd([string]$cmd, [scriptblock]$body) {
      if (Get-Command $cmd -ErrorAction SilentlyContinue) { & $body }
    }

    # eza-based listing (define at global: scope to persist)
    if (Get-Command eza -ErrorAction SilentlyContinue) {
      function global:l { eza --icons=auto --hyperlink @args }
      function global:ll { eza --icons=auto --hyperlink -l @args }
      function global:lsd { eza --icons=auto --hyperlink -alD --sort=created --color=always @args }
    }

    # git shortcuts
    function gs { git status -sb @args }

    # open helper via handlr
    Set-IfCmd 'handlr' { function e { handlr open @args } }

    # grep family via ugrep (ug)
    Set-IfCmd 'ug' {
      function grep  { ug -G @args }
      function egrep { ug -E @args }
      function epgrep { ug -P @args }
      function fgrep { ug -F @args }
      function xgrep { ug -W @args }
      function zgrep { ug -zG @args }
      function zegrep { ug -zE @args }
      function zfgrep { ug -zF @args }
      function zpgrep { ug -zP @args }
      function zxgrep { ug -zW @args }
    }

    # tree
    Set-IfCmd 'erd' { function tree { erd @args } }

    # compression/locate
    Set-IfCmd 'pigz'   { function gzip  { pigz @args } }
    Set-IfCmd 'pbzip2' { function bzip2 { pbzip2 @args } }
    Set-IfCmd 'plocate'{ function locate { plocate @args } }

    # network/disk helpers
    Set-IfCmd 'prettyping' { function ping { prettyping @args } }

    # threads
    Set-IfCmd 'xz'   { function xz   { & xz --threads=0 @args } }
    Set-IfCmd 'zstd' { function zstd { & zstd --threads=0 @args } }

    # mpv controller
    Set-IfCmd 'mpvc' {
      $xdg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
      function mpvc { mpvc -S (Join-Path $xdg 'mpv/socket') @args }
    }
  '';

  shellAliases = {}; # Placeholder, assuming it's defined elsewhere or will be added.
in {
  users.users.neg.maid.file.home = {
    ".config/inputrc".text = inputrc;

    ".config/aliae/config.yaml".text = aliaeConfig;

    ".config/dircolors/dircolors" = {
      source = dircolorsConfig;
    };

    # ZSH Config (generated)
    ".config/zsh".source = zshConfigSource;

    # Also link .zshenv to home if needed?
    # But zshConfigSource puts it in $out/.zshenv.
    # If we link .config/zsh -> zshConfigSource, then .config/zsh/.zshenv exists.
    # Does Zsh read ~/.config/zsh/.zshenv? Only if ZDOTDIR is set before.
    # But ZDOTDIR is set in /etc/zshrc usually or /etc/profile.
    # Let's match existing logic: existing logic constructs a dir.

    # Fish Config
    ".config/fish".source = "${shellFiles}/fish";

    # Fast Syntax Highlighting
    ".config/f-sy-h".source = "${shellFiles}/f-sy-h";

    # PowerShell Profile
    ".config/powershell/Microsoft.PowerShell_profile.ps1".text = pwshProfile;
  };

  # Ensure Config Dirs exist for shells
  # (nix-maid/systemd activation usually handles parents, but we can be safe)
  systemd.tmpfiles.rules = [
    "d ${config.users.users.neg.home}/.config/powershell 0755 neg users -"
  ];

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
