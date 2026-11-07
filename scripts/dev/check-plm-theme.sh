#!/usr/bin/env bash
# Every scene that paints with the palette must read the wallpaper palette.
#
# `theme.plm` carries the roles QS derives at runtime (Settings/Theme.qml:
# `accentPrimary = Color.matchHue(_wpAccent, "#006FCC")`, plus the colours.jsonc
# roles). A scene that names `accent`, `coal`, `slate` or `ink` without importing
# it still compiles and still draws — with the frozen values, so it silently
# ignores the wallpaper while its neighbours follow it. That is what happened to
# the whole shell: the bar and the drawers were converted first, the other five
# scenes kept the theme's own colours, and nothing said so.
#
# Exit: 0 every scene opts in, 1 one does not.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
ROOT="$(repo_root "${1:-}")"
cd "$ROOT"

# The roles theme.plm and palette.plm declare, as an UNQUALIFIED name: a scene
# paints with the frozen role only when it writes `color: coal`, never when it
# writes `live.coal` (lib/palette-live.plm's live copy of it), `notify.ink` (a
# scene's own namespace) or `skin.coal` (the theme's own roles, which is what the
# import is for). The two boundary classes are therefore "not a dot and not a
# word character": a name preceded or followed by a dot belongs to somebody
# else's namespace. That is also why the palette-only shades need no special
# case — `ink.subtle`/`ink.off`/`ink.hover`/`ink.active` are followed by a dot,
# and `veil` is not a role at all (`palette.plm` keeps it for a drawing site).
TOKENS='(^|[^[:alnum:]_.])(accent\.hover|accent\.deep|on\.accent|ink\.dim|accent|coal|slate|ink)([^[:alnum:]_.]|$)'

fail=0
checked=0
while IFS= read -r scene; do
  checked=$((checked + 1))
  body=$(sed -E 's://.*::g; s/"[^"]*"//g' "$scene")
  if printf '%s' "$body" | grep -qE "$TOKENS"; then
    if ! grep -q 'import "../../theme.plm"' "$scene"; then
      echo "FAIL $scene: paints with the palette but does not import theme.plm" >&2
      fail=1
    fi
  fi
done < <(find files/pleamar/shells -mindepth 2 -maxdepth 2 -name '*.plm' | sort)

if [ "$fail" -ne 0 ]; then
  echo "check-plm-theme: $checked scene(s) checked, at least one ignores the wallpaper palette" >&2
  exit 1
fi
echo "ok   plm theme ($checked scenes read theme.plm where they paint with it)"
