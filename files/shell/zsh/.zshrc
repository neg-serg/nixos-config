module_path+=("$HOME/.zi/zmodules/zpmod/Src"); zmodload zi/zpmod 2> /dev/null
FAST_WORK_DIR=~/.config/f-sy-h
source ~/.config/zsh/00-fsyh-parser.zsh

zi_init=${XDG_CONFIG_HOME:-$HOME/.config}/zi/init.zsh
[[ -r $zi_init ]] && . $zi_init && zzinit
[[ -f /etc/NIXOS ]] && fpath=(${ZDOTDIR}/lazyfuncs ${XDG_CONFIG_HOME}/zsh-nix $fpath)
zi ice depth'1' lucid
zi light romkatv/zsh-defer
typeset -f zsh-defer >/dev/null || zsh-defer() { "$@"; }
# F-Sy-H (deferred to next prompt is fine)
# Skip in Distrobox to prevent breakage due to missing dependencies/widgets
if [[ -z "$DISTROBOX_ENTER_PATH" ]]; then
  zi ice depth'1' lucid atinit'typeset -gA FAST_HIGHLIGHT; FAST_HIGHLIGHT[use_async]=1 FAST_HIGHLIGHT[BIND_VI_WIDGETS]=0 FAST_HIGHLIGHT[WIDGETS_MODE]=minimal' wait'0'
  zi load neg-serg/F-Sy-H
fi
# P10k removed in favor of oh-my-posh

# Oh-My-Posh prompt initialization (Cached)
if command -v oh-my-posh >/dev/null 2>&1; then
  omp_config="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/neg.omp.json"
  omp_cache="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-posh-init.zsh"
  
  if [[ -r "$omp_config" ]]; then
    # Rebuild cache if config content has changed (robust against NixOS 1970 mtimes)
    local config_hash
    config_hash=$(md5sum "$omp_config" 2>/dev/null | awk '{print $1}')
    local cache_hash_file="${omp_cache}.md5"
    local stored_hash
    [[ -f "$cache_hash_file" ]] && stored_hash=$(<"$cache_hash_file")

    if [[ ! -r "$omp_cache" || -z "$stored_hash" || "$config_hash" != "$stored_hash" ]]; then
      oh-my-posh init zsh --config "$omp_config" --print > "$omp_cache"
      echo "$config_hash" > "$cache_hash_file"
    fi
    source "$omp_cache"
  fi
fi
# Utilities (deferred)
zi ice depth'1' lucid wait'0'
zi light QuarticCat/zsh-smartcache
source "${ZDOTDIR}/01-init.zsh"
for file in {02-cmds,03-completion,04-bindings,04-fzf,05-neg-cd,07-hishtory,10-opencode-brave}; do
  [[ -r "${ZDOTDIR}/$file.zsh" ]] && zsh-defer source "${ZDOTDIR}/$file.zsh"
done
## Load Aliae aliases after base command aliases to allow Aliae to override them
if [[ -r "${ZDOTDIR}/06-aliae.zsh" ]]; then
  zsh-defer source "${ZDOTDIR}/06-aliae.zsh"
fi
# Last-resort alias fixes
if [[ -r "${ZDOTDIR}/99-fix-aliases.zsh" ]]; then
  zsh-defer source "${ZDOTDIR}/99-fix-aliases.zsh"
fi


[[ $NEOVIM_TERMINAL ]] && source "${ZDOTDIR}/08-neovim-cd.zsh"
# Transient Prompt (must be loaded after prompt setup)
zi ice depth'1' lucid
zi light olets/zsh-transient-prompt

# vim: ft=zsh:nowrap
