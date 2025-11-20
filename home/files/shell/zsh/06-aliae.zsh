# Aliae integration: cross-shell aliases from $XDG_CONFIG_HOME/aliae
if command -v aliae >/dev/null 2>&1; then
  cfg="${XDG_CONFIG_HOME:-$HOME/.config}/aliae/config.yaml"
  # Print init script and eval so aliases override earlier definitions
  eval "$(aliae init zsh --config "$cfg" --print)"
fi
