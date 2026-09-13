# Auto-enable git core.fsmonitor for large repositories (>50k files via index size proxy)
__git_fsmonitor_threshold=$((5 * 1024 * 1024))
__git_fsmonitor_checked=()

_git_fsmonitor_auto_enable() {
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return
  [[ " ${__git_fsmonitor_checked[@]} " =~ " $git_root " ]] && return
  __git_fsmonitor_checked+=("$git_root")
  local index_path="$git_root/.git/index"
  [[ -f "$index_path" ]] || return
  local index_size
  index_size=$(stat -c%s "$index_path" 2>/dev/null) || return
  if (( index_size > __git_fsmonitor_threshold )); then
    git config --local core.fsmonitor true
    echo -e "\033[33m[git]\033[0m enabled core.fsmonitor for \033[36m${git_root##*/}\033[0m ($((index_size / 1024))K index)"
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _git_fsmonitor_auto_enable
