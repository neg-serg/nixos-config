# shellcheck disable=SC1090
skip_global_compinit=1
hm_session_vars="$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"
if [ -r "$hm_session_vars" ]; then
  . "$hm_session_vars"
elif [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
elif [ -r "/etc/profiles/per-user/neg/etc/profile.d/hm-session-vars.sh" ]; then
  . "/etc/profiles/per-user/neg/etc/profile.d/hm-session-vars.sh"
fi
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
if command -v uwsm >/dev/null && uwsm check may-start; then
  exec uwsm start default
fi
