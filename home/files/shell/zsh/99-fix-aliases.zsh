# Fix persistent aliases that might be re-added by plugins
unalias nixos-rebuild 2>/dev/null || true
unsetopt noglob
alias sudo='sudo '
