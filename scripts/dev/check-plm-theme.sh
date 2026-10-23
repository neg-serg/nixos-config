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

# The tokens theme.plm declares. `ink.off`, `ink.subtle`, `ink.hover`, `ink.active`
# and `veil` are palette-only, so a scene may use them without the import.
TOKENS='\b(accent|accent\.hover|accent\.deep|on\.accent|coal|slate|ink|ink\.dim)\b'

fail=0
checked=0
while IFS= read -r scene; do
  checked=$((checked + 1))
  body=$(sed -E 's://.*::g; s/skin\.[a-z.]+//g; s/"[^"]*"//g' "$scene")
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
