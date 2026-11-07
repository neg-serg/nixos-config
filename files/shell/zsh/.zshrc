source @zinit@/share/zinit/zinit.zsh
[[ -f /etc/NIXOS ]] && fpath=(${ZDOTDIR}/lazyfuncs ${XDG_CONFIG_HOME}/zsh-nix $fpath)
zi ice depth'1' lucid
zi light romkatv/zsh-defer
typeset -f zsh-defer >/dev/null || zsh-defer() { "$@"; }
# Syntax highlighting: the Rust engine (zsh-native-syntax). Its theme.ini is
# built from files/shell/zsh-native-syntax/neg.ini by shells.nix, so nothing
# here reads a theme at runtime. F-Sy-H was dropped (2026-10): it needed its
# own theme files plus 00-fsyh-parser.zsh glue, and it only ever loaded as a
# fallback when the Rust module was unavailable.
module_path+=("@native-syntax@/lib/zsh")
source @native-syntax@/lib/zsh/zsh-native-syntax.plugin.zsh
# Powerlevel10k prompt (via zinit)
zi ice depth'1' lucid atload'source ${ZDOTDIR}/.p10k.zsh'
zi load romkatv/powerlevel10k
# Utilities (deferred)
zi ice depth'1' lucid wait'0'
zi light QuarticCat/zsh-smartcache
source "${ZDOTDIR}/01-init.zsh"
for file in {02-cmds,03-completion,04-bindings,04-fzf,05-neg-cd,07-hishtory}; do
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


# vim: ft=zsh:nowrap
