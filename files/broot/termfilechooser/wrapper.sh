# Wrapper for xdg-desktop-portal-termfilechooser: pick paths in broot.
#
# The portal runs it as
#   broot-filechooser <multiple> <directory> <save> <path> <out> <debug>
# and afterwards reads <out>: one absolute path per line, an empty file means
# "cancelled". broot renders its TUI on stderr and its `:print_path` verb writes
# the selection to stdout, so <out> is simply broot's stdout redirect — no
# helper has to parse broot's state.
#
# The @…@ placeholders are filled in by modules/user/xdg.nix.

multiple="${1:-0}"
directory="${2:-0}"
save="${3:-0}"
path="${4:-}"
out="${5:-}"
debug="${6:-0}"

if [[ -z "$out" ]]; then
  printf 'broot-filechooser: the portal passed no selection file\n' >&2
  exit 1
fi

if [[ "$debug" == 1 ]]; then
  set -x
fi

# The "save as" picker verb appends the typed path through this variable.
export TERMFILECHOOSER_OUT="$out"
# A file dialog must not offer to install broot's `br` shell function.
export BR_INSTALL=no

# OpenFile passes the directory to start in, SaveFile passes "<dir>/<name>".
# broot only displays existing paths, so a brand-new save target gets an empty
# placeholder that is removed again unless it is the path that was picked.
start="$path"
created_target=""
if [[ "$save" == 1 ]]; then
  if [[ -z "$start" ]]; then
    start="${HOME:-/}"
  elif [[ ! -e "$start" ]]; then
    parent="$(dirname -- "$start")"
    if [[ -d "$parent" ]] && : > "$start" 2> /dev/null; then
      created_target="$start"
    else
      start="$parent"
    fi
  fi
else
  [[ -d "$start" ]] || start="${HOME:-/}"
fi

picker_dir="@pickerDir@"
conf="$picker_dir/picker.hjson"
flags=()
if [[ "$directory" == 1 ]]; then
  conf="$picker_dir/picker-dir.hjson"
  # Directory dialogs must not offer files at all.
  flags+=(--only-folders)
elif [[ "$multiple" == 1 ]]; then
  conf="$picker_dir/picker-multi.hjson"
fi

# Reuse the user's broot configuration (theme, icons, its own verbs); the
# picker file is read last and therefore wins on conflicting keys.
for user_conf in "$HOME/.config/broot/conf.hjson" "$HOME/.config/broot/conf.toml"; do
  if [[ -f "$user_conf" ]]; then
    conf="$user_conf;$conf"
    break
  fi
done

# broot's stdout has to be the selection file, so it gets a shell of its own
# inside the terminal; the terminal is what the wrapper waits on.
inner="exec $(printf '%q' "@broot@") $(printf '%q' "$start")"
if [[ "$directory" != 1 && -d "$start" ]]; then
  # broot starts with the tree root selected; in a file dialog that line is a
  # directory, so put the selection on the first file instead.
  inner+=" --cmd :line_down"
fi
for flag in "${flags[@]}"; do
  inner+=" $(printf '%q' "$flag")"
done
inner+=" --conf $(printf '%q' "$conf") > $(printf '%q' "$out")"

read -r -a term <<< "${TERMCMD:-@kitty@ --class termfilechooser --title broot}"
term_cmd=""
for word in "${term[@]}"; do
  term_cmd+="$(printf '%q' "$word") "
done

# A failed terminal (or a crash) leaves <out> empty, which the portal already
# treats as "cancelled" — no need to turn it into a louder error.
sh -c "${term_cmd}sh -c $(printf '%q' "$inner")" || true

realpath_or_self() {
  realpath -m -- "$1" 2> /dev/null || printf '%s' "$1"
}

if [[ -n "$created_target" ]]; then
  kept=0
  if [[ -s "$out" ]]; then
    target_real="$(realpath_or_self "$created_target")"
    while IFS= read -r picked; do
      [[ -z "$picked" ]] && continue
      if [[ "$(realpath_or_self "$picked")" == "$target_real" ]]; then
        kept=1
        break
      fi
    done < "$out"
  fi
  if [[ "$kept" == 0 ]]; then
    rm -f -- "$created_target"
  fi
fi
