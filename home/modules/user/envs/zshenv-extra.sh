zshenv_debug() {
  if [[ -n "${ZSHENV_DEBUG:-}" ]]; then
    printf '[zshenv] %s\n' "$@" >&2
  fi
}

if [[ $(readlink -e ~/tmp) == "" ]]; then
  zshenv_debug "Removing broken ~/tmp symlink"
  rm -f ~/tmp
fi
if [[ ! -L ${HOME}/tmp ]]; then
  rm -f ~/tmp
  tmp_loc=$(mktemp -d)
  zshenv_debug "Repointing ~/tmp to ${tmp_loc}"
  ln -fs "${tmp_loc}" "${HOME}/tmp"
fi
if command -v uwsm >/dev/null && uwsm check may-start; then
  zshenv_debug "Delegating shell launch to 'uwsm start default'"
  exec uwsm start default
fi
