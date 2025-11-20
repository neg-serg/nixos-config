{
  lib,
  pkgs,
  config,
  xdg,
  negLib,
  ...
}: let
  filesRoot = "${config.neg.hmConfigRoot}/files";
  zshenvText = let
    username = config.home.username;
    zshenvExtras = builtins.readFile (config.neg.hmConfigRoot + "/modules/user/envs/zshenv-extra.sh");
  in ''
    # shellcheck disable=SC1090
    skip_global_compinit=1
    hm_session_vars="$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"
    if [ -r "$hm_session_vars" ]; then
      . "$hm_session_vars"
    elif [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    elif [ -r "/etc/profiles/per-user/${username}/etc/profile.d/hm-session-vars.sh" ]; then
      . "/etc/profiles/per-user/${username}/etc/profile.d/hm-session-vars.sh"
    fi
    export WORDCHARS='*/?_-.[]~&;!#$%^(){}<>~` '
    export KEYTIMEOUT=10
    export REPORTTIME=60
    export ESCDELAY=1
    ${zshenvExtras}
  '';
  zshConfigSource = pkgs.runCommandLocal "neg-zsh-config" {} ''
    mkdir -p "$out"
    cp -R ${filesRoot + "/shell/zsh"}/. "$out"/
    chmod -R u+w "$out"
    cat > "$out/.zshenv" <<'EOF'
${zshenvText}
EOF
  '';
in
  lib.mkMerge [
  # dircolors, f-sy-h, zsh from dotfiles; inputrc inline
  (xdg.mkXdgSource "dircolors" {
    source = filesRoot + "/shell/dircolors";
    recursive = true;
  })
  (xdg.mkXdgSource "f-sy-h" {
    source = filesRoot + "/shell/f-sy-h";
    recursive = true;
  })
  (xdg.mkXdgText "inputrc" (builtins.readFile ./inputrc))
  (xdg.mkXdgSource "zsh" {
    source = zshConfigSource;
    recursive = true;
    force = true;
  })
  # PowerShell (pwsh) profile under XDG — inline with global functions for eza
  (let
    profileText = ''
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
      # Helpers to define forwarding functions only if the command exists
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

      # cat via bat
      Set-IfCmd 'bat' { function cat { bat -pp @args } }

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

      # wget2 HSTS path
      Set-IfCmd 'wget2' {
        $xdata = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
        function wget { wget2 --hsts-file (Join-Path $xdata 'wget-hsts') @args }
      }
    '';
  in
    lib.mkMerge [
      # Ensure ~/.config/powershell exists as a real directory before writing the profile
      {home.activation.ensurePwshDir = negLib.mkEnsureRealParent "${config.xdg.configHome}/powershell/Microsoft.PowerShell_profile.ps1";}
      (xdg.mkXdgText "powershell/Microsoft.PowerShell_profile.ps1" profileText)
    ])
  # Fish config (conf.d drop-ins)
  (xdg.mkXdgSource "fish" {
    source = filesRoot + "/shell/fish";
    recursive = true;
  })
  # Bash XDG config directory
  (xdg.mkXdgSource "bash" {
    source = filesRoot + "/shell/bash";
    recursive = true;
  })
  # Ensure classic ~/.bashrc sources XDG bashrc
  {
    home.file.".bashrc".text = ''
      # Forward to XDG bashrc managed by Home Manager
      if [ -r "''${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashrc" ]; then
        . "''${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashrc"
      fi
    '';
  }
]
