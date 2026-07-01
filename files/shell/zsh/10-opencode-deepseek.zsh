if [[ -f "/run/secrets/deepseek-api" ]]; then
  export DEEPSEEK_API_KEY="$(cat /run/secrets/deepseek-api)"
fi
