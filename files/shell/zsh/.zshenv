# shellcheck disable=SC1090
skip_global_compinit=1
export WORDCHARS='*/?_-.[]~&;!#$%^(){}<>~` '
export KEYTIMEOUT=10
export REPORTTIME=60
export ESCDELAY=1
[[ $(readlink -e ~/tmp) == "" ]] && rm -f ~/tmp
if [[ ! -L ${HOME}/tmp ]]; then
  rm -f ~/tmp
  tmp_loc=$(mktemp -d)
  ln -fs "${tmp_loc}" "${HOME}/tmp"
fi
