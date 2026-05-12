bindkey -e

autoload -Uz fg-widget && zle -N fg-widget
autoload -Uz imv
autoload -Uz inplace_mk_dirs && zle -N inplace_mk_dirs
autoload -Uz magic-abbrev-expand && zle -N magic-abbrev-expand
autoload -Uz rationalise-dot && zle -N rationalise-dot
autoload -Uz redraw-prompt
autoload -Uz special-accept-line && zle -N special-accept-line
autoload -Uz zleiab && zle -N zleiab
if (( $+commands[zoxide] )); then
  autoload -Uz zoxide_complete
  zle -N zoxide-complete zoxide_complete
  zle -N zoxide-complete-fzf zoxide_complete
fi

_nothing(){}; zle -N _nothing

autoload -Uz cd-rotate
cd-back(){ cd-rotate +1 }
cd-forward(){ cd-rotate -0 }
zle -N cd-back && zle -N cd-forward
bindkey "^[-" cd-forward
bindkey "^[=" cd-back

autoload up-line-or-beginning-search && zle -N up-line-or-beginning-search
autoload down-line-or-beginning-search && zle -N down-line-or-beginning-search

bindkey "^[[A" up-line-or-beginning-search
bindkey "^[OA" up-line-or-beginning-search
bindkey "^[[B" down-line-or-beginning-search
bindkey "^[OB" down-line-or-beginning-search
bindkey "^p" up-line-or-beginning-search
bindkey "^n" down-line-or-beginning-search

bindkey " " magic-abbrev-expand
bindkey . rationalise-dot
bindkey "^xd" describe-key-briefly
bindkey "^Z" fg-widget
bindkey '^M' special-accept-line
bindkey " "  magic-space
bindkey ",." zleiab
bindkey . rationalise-dot
bindkey -M isearch . self-insert # without this, typing a . aborts incremental history search
bindkey '^xm' inplace_mk_dirs # load the lookup subsystem if it's available on the system
if (( $+commands[zoxide] )); then
  # Bind Ctrl-Y and Ctrl-@ to the zoxide fzf widget
  bindkey '^Y' zoxide-complete
  bindkey '^@' zoxide-complete
fi
# Job Management Widgets (Ctrl+S prefix)
jobs_widget() { echo ""; jobs; zle reset-prompt; }
zle -N jobs_widget
bindkey '^S^S' jobs_widget

fg_current_widget() { zle -I; fg %+; }
kill_job_current_widget() { kill %+ && fg %+; }
zle -N fg_current_widget
zle -N kill_job_current_widget

bindkey '^S^M' fg_current_widget
bindkey '^S^K^M' kill_job_current_widget
for i in {1..9}; do
    eval "fg_${i}_widget() { zle -I; fg %${i}; }"
    eval "kill_job_${i}_widget() { kill %${i} && fg %${i}; }"
    eval "zle -N fg_${i}_widget"
    eval "zle -N kill_job_${i}_widget"
    eval "bindkey '^S${i}' fg_${i}_widget"
    eval "bindkey '^S^K${i}' kill_job_${i}_widget"
done

# zoxide_complete provides the fzf-backed picker
# vim: ft=zsh:nowrap
