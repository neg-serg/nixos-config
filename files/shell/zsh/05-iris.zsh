# iris: shell auto-completion that works like IntelliSense (fig-style suggestions).
# Runs its own daemon; hooks line-pre-redraw to show a suggestion menu + ghost text.
# Conflicts with other autosuggestion/autocomplete tools (zsh-autosuggestions,
# zsh-autocomplete, atuin, flyline) — keybindings are adjusted for this stack
# in ~/.config/iris/config.toml (see files/iris/config.toml): Tab inserts
# the top iris suggestion (commands + file paths; native zsh completion on Tab
# is shadowed while iris runs), Ctrl+R is iris history mode (zhist hook
# disabled), Up/Down with closed menu stay in zsh (navigate-closed = "shell").
(( $+commands[iris] )) && eval "$(iris init zsh)"
