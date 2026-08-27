# zhist: smarter history store (dir, exit status, duration) + fzf picker.
# Must load AFTER fzf key-bindings (04-fzf.zsh) — the last Ctrl-R bind wins.
# -no-arrow-binds: keep the up/down history search from 04-bindings.zsh
# (up-line-or-beginning-search / down-line-or-beginning-search).
(( $+commands[zhist] )) && eval "$(zhist init -no-arrow-binds)"
