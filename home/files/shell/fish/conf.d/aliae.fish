#!/usr/bin/env fish
# Aliae integration for fish
if type -q aliae
    set -l cfg (test -n "$XDG_CONFIG_HOME"; and echo "$XDG_CONFIG_HOME/aliae/config.yaml"; or echo "$HOME/.config/aliae/config.yaml")
    aliae init fish --config $cfg --print | source
end

# Fallback aliases (direct) to ensure cross-shell parity
if type -q eza
    alias l 'eza --icons=auto --hyperlink'
    alias ll 'eza --icons=auto --hyperlink -l'
    alias lsd 'eza --icons=auto --hyperlink -alD --sort=created --color=always'
end
alias gs 'git status -sb'
type -q handlr; and alias e 'handlr open'
type -q bat; and alias cat 'bat -pp'
if type -q ug
    alias grep  'ug -G'
    alias egrep 'ug -E'
    alias epgrep 'ug -P'
    alias fgrep 'ug -F'
    alias xgrep 'ug -W'
    alias zgrep 'ug -zG'
    alias zegrep 'ug -zE'
    alias zfgrep 'ug -zF'
    alias zpgrep 'ug -zP'
    alias zxgrep 'ug -zW'
end
type -q erd; and alias tree 'erd'
type -q pigz; and alias gzip 'pigz'
type -q pbzip2; and alias bzip2 'pbzip2'
type -q plocate; and alias locate 'plocate'
type -q prettyping; and alias ping 'prettyping'
type -q xz; and alias xz 'xz --threads=0'
type -q zstd; and alias zstd 'zstd --threads=0'
type -q mpvc; and alias mpvc 'mpvc -S "$XDG_CONFIG_HOME/mpv/socket"'
type -q wget2; and alias wget 'wget2 --hsts-file "$XDG_DATA_HOME/wget-hsts"'
