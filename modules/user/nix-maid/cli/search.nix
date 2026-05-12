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
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.bat # A cat(1) clone with wings (syntax highlighting)
        pkgs.fzf # A command-line fuzzy finder
        pkgs.fd # A simple, fast and user-friendly alternative to 'find'
        pkgs.ripgrep # Line-oriented search tool (grep alternative)
      ];

      # --- Environment Variables ---
      environment.variables = {
        RIPGREP_CONFIG_PATH = "${config.users.users.neg.home}/.config/ripgrep/ripgreprc";

        FZF_DEFAULT_COMMAND = "${lib.getExe pkgs.fd} --type=f --hidden --exclude=.git"; # Simple, fast and user-friendly alternative to find
        FZF_DEFAULT_OPTS = builtins.concatStringsSep " " (
          builtins.filter (x: builtins.typeOf x == "string") [
            "--bind='alt-p:toggle-preview,alt-a:select-all,alt-s:toggle-sort'"
            "--bind='alt-d:change-prompt(Directories ❯ )+reload(fd . -t d)'"
            "--bind='alt-f:change-prompt(Files ❯ )+reload(fd . -t f)'"
            "--bind='ctrl-j:execute(v {+})+abort'"
            "--bind='ctrl-space:select-all'"
            "--bind='ctrl-t:accept'"
            "--bind='ctrl-v:execute(v {+})'"
            "--bind='ctrl-y:execute-silent(echo {+} | wl-copy)'"
            "--bind='tab:execute(handlr open {+})+abort'"
            "--ansi"
            "--layout=reverse"
            "--cycle"
            "--border=sharp"
            "--margin=0"
            "--padding=0"
            "--footer='[Alt-f] Files  [Alt-d] Dirs  [Alt-p] Preview  [Alt-s] Sort  [Tab] Open'"
            "--color=header:white"
            "--color=footer:underline"
            "--color=footer:white"
            "--exact"
            "--height=16"
            "--min-height=14"
            "--info=default"
            "--multi"
            "--no-mouse"
            "--no-scrollbar"
            "--prompt='❯  '"
            "--pointer=▶"
            "--marker=✓"
            "--with-nth=1.."
            # Colors
            "--color=preview-bg:-1"
            "--color=gutter:#000000"
            "--color=bg:#000000"
            "--color=bg+:#000000"
            "--color=fg:#4f5d78"
            "--color=fg+:#8DA6B2"
            "--color=hl:#546c8a"
            "--color=hl+:#005faf"
            "--color=border:#0b2536"
            "--color=list-border:#0b2536"
            "--color=input-border:#0b2536"
            "--color=preview-border:#000000"
            "--color=header-border:#0b2536"
            "--color=footer-border:#0b2536"
            "--color=separator:#0b2536"
            "--color=scrollbar:#0b2536"
            "--color=info:#3f5876"
            "--color=pointer:#005faf"
            "--color=marker:#04141C"
            "--color=prompt:#005faf"
            "--color=spinner:#3f5876"
            "--color=preview-fg:#4f5d78"
          ]
        );

        FZF_CTRL_R_OPTS = builtins.concatStringsSep " " [
          "--sort"
          "--exact"
          "--border=sharp --margin=0 --padding=0 --no-scrollbar"
          "--footer='[Enter] Paste  [Ctrl-y] Yank  [?] Preview'"
          "--preview 'echo {}'"
          "--preview-window down:5:hidden,wrap --bind '?:toggle-preview'"
        ];

        FZF_CTRL_T_OPTS = builtins.concatStringsSep " " [
          ''--border=sharp --margin=0 --padding=0 --no-scrollbar --preview 'if [ -d "{}" ]; then (eza --tree --icons=auto -L 2 --color=always "{}" 2>/dev/null || tree -C -L 2 "{}" 2>/dev/null); else (bat --style=plain --color=always --line-range :200 "{}" 2>/dev/null || highlight -O ansi -l "{}" 2>/dev/null || head -200 "{}" 2>/dev/null || file -b "{}" 2>/dev/null); fi' --preview-window=right,60%,border-left,wrap''
        ];
      };
    }

    (n.mkHomeFiles {
      # Bat Config (syntaxes disabled due to HM batCache conflict)
      ".config/bat/config".text = ''
        --theme="ansi"
        --italic-text="always"
        --paging="never"
        --decorations="never"
      '';

      # FD Ignore
      ".config/fd/ignore".text = ''
        .git/
      '';

      # Ripgrep Config
      ".config/ripgrep/ripgreprc".text = ''
        --no-heading
        --smart-case
        --follow
        --hidden
        --glob=!.git/
        --glob=!node_modules/
        --glob=!yarn.lock
        --glob=!package-lock.json
        --glob=!.yarn/
        --glob=!_build/
        --glob=!tags
        --glob=!.pub-cache
      '';
    })
  ];
}
