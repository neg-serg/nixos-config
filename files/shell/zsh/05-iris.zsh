# iris: shell auto-completion that works like IntelliSense (fig-style suggestions).
# Runs its own daemon; hooks line-pre-redraw to show a suggestion menu + ghost text.
# Conflicts with other autosuggestion/autocomplete tools (zsh-autosuggestions,
# zsh-autocomplete, atuin, flyline) — keybindings are adjusted for this stack
# in ~/.config/iris/config.toml (see files/iris/config.toml): Tab stays with
# zsh (fzf-on-tab completion + ~/m/new fuzzy expansion); the iris ghost
# suggestion is accepted with -> (navigate-right) or Ctrl+P/Ctrl+N + Enter.
# Ctrl+R is iris history mode (zhist hook disabled).
(( $+commands[iris] )) && eval "$(iris init zsh)"
