# iris: shell auto-completion (IntelliSense-style suggestions) + history picker.
# Tab/fzf-on-tab (04-fzf.zsh) handles completion and ~/m/new expansion; iris
# provides the spec/AI ghost (accepted with -> or Tab when pending) and the
# Ctrl+R history picker (toggle-mode = "ctrl+r", zhist removed).
(( $+commands[iris] )) && eval "$(iris init zsh)"
