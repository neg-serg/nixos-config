# 09-fm.zsh — fm: kitty's built-in fuzzy file finder (choose-files kitten)
#              used as a file manager.
#
# fm [dir] — pick any path (file or dir) with the kitty choose-files UI:
#   type to fuzzy-filter, arrows to move, Enter to pick, Tab to enter a
#   directory. A picked directory -> cd into it; a picked file -> open with
#   the default handler (handlr). Run inside kitty.
#
# The raw picker is also bound in kitty as Ctrl+Shift+P (key.conf:
# kitty_mod+p -> kitten choose_files); when invoked from a mapping at a
# shell prompt, the chosen path is inserted at the cursor instead of being
# printed to stdout.

fm() {
  local root="${1:-$PWD}"
  [[ -d "$root" ]] || root="$PWD"
  if ! command -v kitten >/dev/null 2>&1; then
    print -u2 "fm: kitten not found — fm runs inside kitty (Ctrl+Shift+P is the raw picker)"
    return 127
  fi

  local picked
  picked="$(kitten choose-files --mode=all -- "$root")" || return $?
  [[ -n "$picked" ]] || return 1

  if [[ -d "$picked" ]]; then
    builtin cd -- "$picked"
  else
    handlr open -- "$picked"
  fi
}
