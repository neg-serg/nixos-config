# vi mode: Esc enters command mode (native hjkl/G/gg/u); insert mode keeps the
# emacs chords via the viins layer at the bottom of this file. All binds below
# land in viins because `bindkey -v` makes it the main keymap.
bindkey -v

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

bindkey . rationalise-dot
bindkey "^xd" describe-key-briefly
# ^Z suspends again (zle has no built-in suspend widget, so wrap the builtin);
# the old fg helper moved to C-x f.
suspend_widget() { zle -I; suspend }
zle -N suspend_widget
bindkey -M viins '^Z' suspend_widget
bindkey -M vicmd '^Z' suspend_widget
bindkey -M viins '^Xf' fg-widget
bindkey '^M' special-accept-line
bindkey " "  magic-space
bindkey ",." zleiab
bindkey -M isearch . self-insert # without this, typing a . aborts incremental history search
bindkey '^xm' inplace_mk_dirs # load the lookup subsystem if it's available on the system
if (( $+commands[zoxide] )); then
  # zoxide lives on ^G alone: ^Y has to stay yank (bound in the viins-emacs
  # layer below) and ^@ drives the Tab-less fzf completion (04-fzf.zsh). The
  # old ^Y/^@ pair swallowed both.
  bindkey '^G' zoxide-complete
fi
# Job Management Widgets (C-x prefix; ^S is left to incremental search)
jobs_widget() { echo ""; jobs; zle reset-prompt; }
zle -N jobs_widget

kill_job_current_widget() { kill %+ && fg %+; }
zle -N kill_job_current_widget

bindkey '^Xj' jobs_widget
bindkey '^Xk' kill_job_current_widget
for i in {1..9}; do
    eval "fg_${i}_widget() { zle -I; fg %${i}; }"
    eval "kill_job_${i}_widget() { kill %${i} && fg %${i}; }"
    eval "zle -N fg_${i}_widget"
    eval "zle -N kill_job_${i}_widget"
    eval "bindkey '^X${i}' fg_${i}_widget"
    eval "bindkey '^Xk${i}' kill_job_${i}_widget"
done

# zoxide_complete provides the fzf-backed picker

# --- vi insert-mode emacs layer --------------------------------------------
# viins leaves ^A/^B/^E/^F/^K unbound (self-insert) and has no Alt(word)
# chords; command mode already carries the native vi keys, so this layer is
# additive. ^U/^W keep the vim defaults (kill line / kill word). The ^R bind
# here is the no-fzf fallback: 04-fzf.zsh later points ^R (viins included) at
# fzf-history-widget.
bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^B' backward-char
bindkey -M viins '^E' end-of-line
bindkey -M viins '^F' forward-char
bindkey -M viins '^K' kill-line
bindkey -M viins '^Y' yank
bindkey -M viins '^R' history-incremental-search-backward
bindkey -M viins '^S' history-incremental-search-forward
bindkey -M viins '^[b' backward-word
bindkey -M viins '^[d' kill-word
bindkey -M viins '^[f' forward-word

# vim: ft=zsh:nowrap
