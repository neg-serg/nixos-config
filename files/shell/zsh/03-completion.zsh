# carapace: rich described completion for 300+ CLIs (git, docker, nix,
# kubectl, gh, ...). Sourced after compinit (eager in 01-init) so compdef
# and the _carapace completer wire up.
if (( $+commands[carapace] )); then
  source <(carapace _carapace zsh)
fi

zstyle ':acceptline:*' rehash true
# allow one error for every three characters typed in approximate completer
zstyle ':completion:*:approximate:' max-errors 'reply=( $((($#PREFIX+$#SUFFIX)/3 )) numeric )'
# don't complete backup files as executables
zstyle ':completion:*:complete:-command-::commands' ignored-patterns '*\~'
# start menu completion only if it could find no unambiguous initial string
zstyle ':completion:*:correct:*' insert-unambiguous true
zstyle ':completion:*:corrections' format "%{${fg[blue]}%}--%{${reset_color}%} %d%{${reset_color}%} - (%{${fg[cyan]}%}errors %e%{${reset_color}%})"
zstyle ':completion:*:descriptions' format "%{${fg[blue]}%}--%{${reset_color}%} %d%{${reset_color}%}%{${reset_color}%}"
zstyle ':completion:*:correct:*' original true
zstyle ':completion:*:-tilde-:*' group-order 'named-directories'
# Don't complete unavailable commands.
zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec))'
# insert all expansions for expand completer
zstyle ':completion:*:expand:*' tag-order all-expansions
zstyle ':completion:*:history-words' list false
# autorehash for completion
zstyle ':completion:*' rehash true
# match uppercase from lowercase
zstyle ':completion:*' matcher-list '' \
  '+m:{[:lower:]}={[:upper:]}' \
  '+m:{[:upper:]}={[:lower:]}' \
  '+m:{_-}={-_}' \
  'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
# automatically load bash completion functions
autoload -Uz bashcompinit && bashcompinit
# separate matches into groups
zstyle ':completion:*:matches' group 'yes'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=5
zstyle ':completion:*:messages' format "- %{${fg[cyan]}%}%d%{${reset_color}%} -"
zstyle ':completion:*:options' auto-description '%d'
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters
zstyle ':completion:*' verbose true
zstyle ':completion:*:-command-:*:' verbose false
zstyle ':completion:*:warnings' format $'%{\e[0;31m%}No matches for:%{\e[0m%} %d'
zstyle ':completion:*:*:zcompile:*' ignored-patterns '(*~|*.zwc)'
zstyle ':completion:correct:' prompt 'correct to: %e'
zstyle ':completion::(^approximate*):*:functions' ignored-patterns '_*'
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.*' insert-sections true
zstyle ':completion:*:man:*' menu yes select
zstyle ':completion:*' special-dirs ..
zstyle ':completion:*:(mv|cp|file|mp|mpv|mpa|mpi):*' ignored-patterns '(#i)*.(url|mht)'
zstyle ':completion:*:*:(mp|mpv|mpa|mpi):*' tag-order files
zstyle ':completion:*:*:(mp|mpv|mpa|mpi):*' file-sort name
zstyle ':completion:*:*:(mp|mpv|mpa|mpi):*' menu select auto
zstyle ':completion:*:*:(mp|mpv|mpa|mpi):*' file-patterns '(#i)*.(rmvb|mkv|vob|ts|mp4|m4a|iso|wmv|webm|flv|ogv|avi|mpg|mpeg|iso|nrg|mp3|alac|ogg|flac|rm|wv|m4v):files:mpv\ play *(-/):directories:directories'
zstyle ':completion:*:*:(wine|wine64):*' file-patterns '*.exe:files:wine\ exec *(-/):directories:directories'
# list-colors from LS_COLORS. NOTE: use %%:ec=* (not %ec=*) — the short
# suffix match "ec=*" also hits inside "*.gemspec=…", truncating that entry
# and breaking fzf-tab's namecolors parse ("bad set of key/value pairs").
#
# list-colors values are SGR parameters (zsh wraps them in \e[…m), so the
# palette is spelled out below: $color[…]/$fg[…] resolve through the terminal's
# 16-colour table, which no longer carries the theme. The hexes are the ones
# files/shell/dircolors/dircolors and files/shell/zsh-native-syntax/neg.ini use.
typeset -gA negcolor
negcolor=(
    black    '38;2;0;0;0'
    ops1     '38;2;54;124;176'
    ops3     '38;2;0;95;175'
    dlim     '38;2;71;121;179'
    lit2     '38;2;20;135;135'
    lit3     '38;2;18;122;87'
    dwarn    '38;2;200;168;239'
    high     '38;2;165;193;230'
    bold     '01'
    bg_black '48;2;0;0;0'
)
zstyle ':completion:*:default' select-prompt \
    "%F{#148787}Match %B%F{#a5c1e6}%m%F{#148787} Line %B%F{#a5c1e6}%l%F{#367cb0} %p%f%b"
    zstyle ':completion:*:default' \
    list-prompt "%F{#148787}Line %B%F{#a5c1e6}%l%F{#148787}  Continue?%f%b"
    zstyle ':completion:*:warnings' \
    format "- %F{#367cb0}no match%f - %F{#148787}%d%f"
zstyle ":completion:*" list-colors ${(s.:.)LS_COLORS%%:ec=*} "ma=07;01;38;2;0;0;0;48;2;0;95;175"
zstyle ':completion:*:options' list-colors '=^(-- *)=00;38;2;0;95;175'
zstyle ':completion:*' squeeze-slashes true # e.g. ls foo//bar -> ls foo/bar
# highlight the original input.
zstyle ':completion:*:original' list-colors "=*=${negcolor[ops1]};${negcolor[bold]}"
# colorize username completion
zstyle ':completion:*:*:*:*:users' list-colors "=*=${negcolor[ops1]};${negcolor[bg_black]}"
zstyle ':completion:*:wine:*' file-patterns '(#i)*.(exe):exe'
# highlight parameters with uncommon names
zstyle ':completion:*:parameters' list-colors "=[^a-zA-Z]*=${negcolor[lit2]}"
# highlight aliases
zstyle ':completion:*:aliases' list-colors "=*=${negcolor[lit3]}"
# highlight words like 'esac' or 'end'
zstyle ':completion:*:reserved-words' list-colors "=*=${negcolor[ops1]}"
# colorize processlist for 'kill'
zstyle ':completion:*:*:kill:*:processes' list-colors "=(#b) #([0-9]#) #([^ ]#)*=${negcolor[lit2]}=${negcolor[dwarn]}=${negcolor[lit3]}"
zstyle ':completion:*:*:kill:*:processes' command 'ps --forest -e -o pid,user,tty,cmd'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:zathura:*' tag-order files
zstyle ':completion:*:*:zathura:*' file-patterns '*(/)|*.{pdf,djvu}'
# make them a little less short, after all (mostly adds -l option to the whatis calll)
zstyle ':completion:*:command-descriptions' command '_call_whatis -l -s 1 -r .\*; _call_whatis -l -s 6 -r .\* 2>/dev/null'
# Filename suffixes to ignore during completion (except after rm command)
zstyle ':completion:*:*:(^rm):*:*files' ignored-patterns '*?.o' '*?.c~' '*?.old' '*?.pro'
# Use caching so that commands like apt and dpkg complete are useable
zstyle ':completion::complete:*' use-cache 1
zstyle ':completion::complete:*' cache-path $ZSH_CACHE_DIR

autoload -U select-word-style backward-kill-word-match backward-word-match forward-word-match
select-word-style shell

zle -N backward-kill-word-match
zle -N backward-word-match
zle -N forward-word-match

# for backward-kill, all but / are word chars (ie, delete word up to last directory)
zstyle ':zle:backward-kill-word*' word-style standard
zstyle ':zle:*kill*' word-chars '*?_-.[]~=&;!#$%^(){}<>'

zshcache_time="$(date +%s%N)"
autoload -Uz add-zsh-hook

# vim: ft=zsh:nowrap

# `y` (02-cmds.zsh) browses directories.
if (( $+functions[compdef] )); then
  compdef '_files -/' y
fi
