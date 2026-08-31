# 09-fm.zsh — fzf as a file manager (fm)
#
# fm [dir] — browse the filesystem with fzf:
#   Enter       on a directory -> cd into it and keep browsing
#               on a file      -> open with the default handler (handlr), then
#                                  cd the shell to the browsed dir and exit
#   alt-enter                   -> edit the file with $EDITOR, keep browsing
#   alt-up      (or '..' entry) -> go up to the parent directory
#   ctrl-o                      -> open with the default handler, stay in fzf
#   ctrl-y                      -> copy the absolute path to the clipboard
#   alt-p / ?                   -> toggle the preview pane
#
# Listing: current directory, depth 1, hidden files included, heavy dirs
# skipped (same excludes as the fzf path-completion walker in 04-fzf.zsh).
# Preview: dirs -> eza tree; images -> magick + chafa; other files -> bat.

fm() {
  local dir="${1:-$PWD}"
  [[ -d "$dir" ]] || dir="$PWD"
  dir="${dir:a}" # absolute path, keep symlinks

  # fd exclude list must stay in sync with _fzf_compgen_path in 04-fzf.zsh
  local excludes=(--exclude .git --exclude node_modules --exclude .cache --exclude .local --exclude .dsh --exclude .var)

  local preview='
    if [ -d "{}" ]; then
      eza --tree --icons=auto -L 2 --color=always "{}" 2>/dev/null \
        || tree -C -L 2 "{}" 2>/dev/null
    elif [[ "{}" =~ \.(png|jpe?g|webp|gif|svg|bmp|avif|tiff?)$ ]]; then
      magick "{}" -auto-orient -resize 800x png:- 2>/dev/null \
        | chafa --format symbols --colors 256 --size 50x30 - 2>/dev/null \
        || chafa --format symbols --colors 256 --size 50x30 "{}" 2>/dev/null
    else
      bat --style=plain --color=always --line-range :300 "{}" 2>/dev/null \
        || file -b "{}" 2>/dev/null
    fi'

  local qdir="${(q)dir}" out key sel
  while true; do
    out="$(
      cd -- "$dir" || return 1
      {
        printf '..\n'
        command fd -H -t d -d 1 --no-ignore "${excludes[@]}" .
        command fd -H -t f -d 1 --no-ignore "${excludes[@]}" .
      } | fzf \
        --no-multi \
        --no-exact \
        --expect=alt-up,alt-enter \
        --height=100% \
        --prompt 'FM ❯ ' \
        --preview "$preview" \
        --preview-window 'right,60%,border-left' \
        --bind '?:toggle-preview' \
        --bind "ctrl-o:execute-silent(handlr open -- ${qdir}/{})" \
        --bind "ctrl-y:execute-silent(printf '%s\n' ${qdir}/{} | wl-copy)" \
        --header 'Enter: open  alt-enter: edit  alt-up: up  ctrl-o: open+stay  ctrl-y: copy  ?: preview'
    )" || return 1

    key="${out%%$'\n'*}"
    sel="${out#*$'\n'}"
    [[ -n "$sel" ]] || return 1

    case "$key" in
      alt-up)    dir="${dir:h}"; continue ;;
      alt-enter) ${EDITOR:-$(command -v nvim)} -- "$dir/$sel"; continue ;;
    esac

    [[ "$sel" == ".." ]] && { dir="${dir:h}"; continue; }
    if [[ -d "$dir/$sel" ]]; then
      dir="${dir%/}/$sel"
      continue
    fi

    handlr open -- "$dir/$sel"
    builtin cd -- "$dir"
    return 0
  done
}
