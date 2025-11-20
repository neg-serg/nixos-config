[[ -o interactive ]] || return 0
[[ -n "${HISHTORY_ZSH_CONFIG:-}" && -r "${HISHTORY_ZSH_CONFIG}" ]] || return 0
_hishtory_config_path="${HOME}/.hishtory/.hishtory.config"
if [[ ! -f "${_hishtory_config_path}" ]]; then
  unset _hishtory_config_path
  return 0
fi
unset _hishtory_config_path

# Let hiSHtory own Ctrl+R (fzf binds it by default)
_hishtory_ctrl_r_binding="$(bindkey '^R' 2>/dev/null || true)"
if [[ "${_hishtory_ctrl_r_binding:-}" == *"fzf-history-widget"* ]]; then
  bindkey -r '^R'
fi
unset _hishtory_ctrl_r_binding

# Official hiSHtory hook (path exported via HISHTORY_ZSH_CONFIG)
source "${HISHTORY_ZSH_CONFIG}"
