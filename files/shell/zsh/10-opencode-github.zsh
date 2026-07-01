if [[ -f "/run/secrets/github-token" ]]; then
  export GITHUB_TOKEN="$(cat /run/secrets/github-token)"
fi
