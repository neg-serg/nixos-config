[[ $(readlink -e ~/tmp) == "" ]] && rm -f ~/tmp
if [[ ! -L ${HOME}/tmp ]]; then
  rm -f ~/tmp
  tmp_loc=$(mktemp -d)
  ln -fs "${tmp_loc}" "${HOME}/tmp"
fi
