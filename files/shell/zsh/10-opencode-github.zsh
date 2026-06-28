if [[ -f "/run/user/1000/secrets/github-token" ]]; then
  export GITHUB_TOKEN="$(cat /run/user/1000/secrets/github-token)"
fi
