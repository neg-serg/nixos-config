# iris: shell auto-completion that works like IntelliSense (fig-style suggestions).
# Runs its own daemon; hooks line-pre-redraw to show a suggestion menu + ghost text.
# Conflicts with other autosuggestion/autocomplete tools (zsh-autosuggestions,
# zsh-autocomplete, atuin, flyline) — keybindings are adjusted for this stack
# in ~/.config/iris/config.toml + packages/iris/iris-tab-ghost.patch:
# Tab inserts the iris ghost suggestion when one is pending, otherwise falls
# through to zsh (fzf-on-tab completion + ~/m/new fuzzy expansion). -> also
# accepts the ghost; Ctrl+P/Ctrl+N cycle it. Ctrl+R = iris history mode.
(( $+commands[iris] )) && eval "$(iris init zsh)"
