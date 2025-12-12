_: {
  programs.bash = {
    interactiveShellInit = ''
      shopt -qs autocd # cd without typing cd
      shopt -qs cdspell # Auto-correct directory typos
      shopt -qs checkhash # Check hash before executing
      shopt -s checkwinsize # Check window size after each command, and update $LINES and $COLUMNS
      shopt -s cmdhist # Save all lines of multiline commands
      shopt -qs direxpand # Expand directory names when doing file completion
      shopt -qs dirspell # Fix typos for directories in completion
      shopt -qs dotglob # Include filenames that begin with '.' in filename expansion
      shopt -qs extglob # Extended pattern matching
      shopt -qs extquote # Allow escape sequencing within $parameter expansions
      shopt -qs globstar # Support ** for expansion
      shopt -qs histappend histreedit histverify
      shopt -qs hostcomplete
      shopt -s nocaseglob nocasematch

      any(){
          [ -n "$1" ] && ps uwwwp $(pgrep -f "$@")
      }

      bind 'set show-all-if-ambiguous on'
      bind 'set completion-ignore-case on'
      bind 'set completion-map-case on'
      bind 'TAB:menu-complete'
      bind 'set mark-symlinked-directories on'

      HISTFILESIZE=100000
      HISTCONTROL="erasedups:ignoreboth"
      export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
      HISTTIMEFORMAT='%F %T '

      # oh-my-posh init handled by Home Manager (core-tools.nix)
    '';
    shellAliases = {
      ":q" = "exit";
      "dd" = "dd status=progress";
      "k" = "kubectl";
      "l" = "ls";
      "ll" = "ls -lah";
      "ls" = "ls --time-style=+\"%d.%m.%Y %H:%M\" --color=auto --hyperlink=auto";
      "mk" = "mkdir -p";
      "mv" = "mv -i";
      "rd" = "rmdir";
      "sort" = "sort --parallel 8 -S 16M";
      "v" = "vim";
      "gd" = "git diff -w -U0 --word-diff-regex=[^[:space:]]";
      "gp" = "git push";
      "gs" = "git status --short -b";
      "add" = "git add";
      "checkout" = "git checkout";
      "fetch" = "git fetch";
      "pull" = "git pull";
      "push" = "git push";
      "stash" = "git stash";
      "status" = "git status";
      "commit" = "git commit";
    };
  };
}
