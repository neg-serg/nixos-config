# Resolve fzf dir (prefer fzf-share)
local _fzf_dir
if (( ${+commands[fzf-share]} )); then
  _fzf_dir="$(fzf-share 2>/dev/null)"
elif [[ -d /usr/share/fzf ]]; then
  _fzf_dir=/usr/share/fzf
else
  return 0
fi

# Empty trigger: fzf-completion fires on plain Tab (no '**' needed) so path
# completion can match abbreviated middle components (~/m/new -> ~/music/new).
# fzf-on-tab only routes path-like words here, so command completion is untouched.
export FZF_COMPLETION_TRIGGER=''

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

# completion.zsh routes its fzf invocation through _fzf_comprun when it is a
# function (same hook fzf-tab uses). Our path completion depends on
# --scheme=path prefix matching, which the global FZF_DEFAULT_OPTS disables
# with --exact (e.g. search.nix). Strip --exact for these runs only;
# every other fzf invocation keeps the global opts untouched.
_fzf_comprun() {
  shift                                  # drop the leading command-word argument
  local opts=${FZF_DEFAULT_OPTS// --exact/}
  opts=${opts//--exact /}
  FZF_DEFAULT_OPTS=$opts fzf "$@"
}

bindkey "^I" fzf-on-tab   # empty line -> fzf file picker; path word -> fuzzy; else normal completion
