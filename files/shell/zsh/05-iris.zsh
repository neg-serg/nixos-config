# iris: shell auto-completion that works like IntelliSense (fig-style suggestions).
# Runs its own daemon; hooks line-pre-redraw to show a suggestion menu + ghost text.
# Conflicts with other autosuggestion/autocomplete tools (zsh-autosuggestions,
# zsh-autocomplete, atuin, flyline) — keybindings are adjusted for this stack
# in ~/.config/iris/config.toml (see files/iris/config.toml): Tab stays with
# plain zsh completion (iris select disabled), Ctrl+R stays with zhist (iris
# toggle-mode -> ctrl+g), Up/Down with closed menu stay in zsh
# (navigate-closed = "shell").
(( $+commands[iris] )) && eval "$(iris init zsh)"
