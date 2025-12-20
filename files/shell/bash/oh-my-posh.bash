if command -v oh-my-posh > /dev/null 2>&1; then
  omp_config="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/neg.omp.json"
  if [ -r "$omp_config" ]; then
    eval "$(oh-my-posh init bash --config "$omp_config" --print)"
  fi
fi
