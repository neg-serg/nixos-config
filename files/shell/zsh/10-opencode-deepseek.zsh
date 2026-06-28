if [[ -f "/run/user/1000/secrets/deepseek-api" ]]; then
  export DEEPSEEK_API_KEY="$(cat /run/user/1000/secrets/deepseek-api)"
fi
