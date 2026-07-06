source @zinit@/share/zinit/zinit.zsh
FAST_WORK_DIR=~/.config/f-sy-h
source ~/.config/zsh/00-fsyh-parser.zsh
[[ -f /etc/NIXOS ]] && fpath=(${ZDOTDIR}/lazyfuncs ${XDG_CONFIG_HOME}/zsh-nix $fpath)
zi ice depth'1' lucid
zi light romkatv/zsh-defer
typeset -f zsh-defer >/dev/null || zsh-defer() { "$@"; }
# Native Rust syntax highlighting module (primary)
module_path+=("@native-syntax@/lib/zsh")
source @native-syntax@/lib/zsh/zsh-native-syntax.plugin.zsh
# F-Sy-H (deferred, secondary — provides file-ext styles)
# Only load if zsh-native-syntax (primary) is not available, to avoid widget conflicts
if [[ -z "$DISTROBOX_ENTER_PATH" ]] && ! zmodload -F zsh_native_syntax 2>/dev/null && [[ ! -r "${module_path[-1]}/zsh_native_syntax.so" ]]; then
  zi ice depth'1' lucid atinit'typeset -gA FAST_HIGHLIGHT; FAST_HIGHLIGHT[use_async]=1 FAST_HIGHLIGHT[BIND_VI_WIDGETS]=0 FAST_HIGHLIGHT[WIDGETS_MODE]=minimal' wait'0'
  zi load neg-serg/F-Sy-H
fi
# Powerlevel10k prompt (via zinit)
zi ice depth'1' lucid atload'source ${ZDOTDIR}/.p10k.zsh'
zi load romkatv/powerlevel10k
# Utilities (deferred)
zi ice depth'1' lucid wait'0'
zi light QuarticCat/zsh-smartcache
source "${ZDOTDIR}/01-init.zsh"
for file in {02-cmds,03-completion,04-bindings,04-fzf,05-neg-cd,07-hishtory,10-opencode-github,10-opencode-deepseek}; do
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
# vim: ft=zsh:nowrap
