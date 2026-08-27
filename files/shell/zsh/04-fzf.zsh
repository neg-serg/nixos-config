# Resolve fzf dir (prefer fzf-share)
local _fzf_dir
if (( ${+commands[fzf-share]} )); then
  _fzf_dir="$(fzf-share 2>/dev/null)"
elif [[ -d /usr/share/fzf ]]; then
  _fzf_dir=/usr/share/fzf
else
  return 0
fi

local _fzf_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf"
[[ -d "$_fzf_cache_dir" ]] || mkdir -p -- "$_fzf_cache_dir"

# Sync files if missing/empty or older than source
for f in key-bindings.zsh completion.zsh; do
  local src="${_fzf_dir}/${f}" dst="${_fzf_cache_dir}/${f}"
  [[ -r "$src" ]] || continue
  [[ -s "$dst" && ! "$src" -nt "$dst" ]] || cp -f -- "$src" "$dst"
done

# Make sure completion infra exists before fzf completion
autoload -Uz compinit
(( ${+_comps} )) || compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

# Load (zsh will prefer compiled .zwc if present)
source "${_fzf_cache_dir}/key-bindings.zsh" 2>/dev/null
source "${_fzf_cache_dir}/completion.zsh"   2>/dev/null

# Fast candidate sources for fzf path completion (replaces the default fzf
# walker, which would recursively walk huge roots like $HOME). fd with depth
# limit + excludes keeps ~/m/new fuzzy completion instant.
# NOTE: .local/.cache are skipped, so paths under them are not fuzzy-completed
# (plain Tab completion still works there).
_fzf_compgen_path() {
  command fd -H -t f -t d -d 8 \
    --exclude .cache --exclude .local --exclude .git \
    --exclude node_modules --exclude .dsh --exclude .var \
    . "$1" 2>/dev/null
}
_fzf_compgen_dir() {
  command fd -H -t d -d 8 \
    --exclude .cache --exclude .local --exclude .git \
    --exclude node_modules --exclude .dsh --exclude .var \
    . "$1" 2>/dev/null
}

# Fast fuzzy completion (no TUI): fzf-on-tab resolves words whose parent dir
# is missing via fzf-path-insert, which runs `fd | fzf --scheme=path --filter`
# non-interactively and INSERTS the best match on Tab. The global
# FZF_DEFAULT_OPTS --exact (search.nix) is stripped there; other fzf
# invocations (Ctrl-T/Ctrl-R pickers) keep their opts untouched.
bindkey "^I" fzf-on-tab   # empty line -> fzf file picker; path word -> insert best match; else normal completion
