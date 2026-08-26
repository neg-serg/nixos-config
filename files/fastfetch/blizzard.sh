#!/bin/bash
# regenerate blizzard-*.webp variants (dither x palette) into XDG_DATA_HOME/fastfetch/logos
set -e
cd "$(dirname "$0")"
if [ -z "$1" ]; then
  dithers="fs atkinson sierra stucki bayer noise"
else
  dithers="$1"
fi
for d in $dithers; do
  for pal in ash ember ice; do
    python3 make_blizzard.py --dither "$d" --palette "$pal" --out "$HOME/.local/share/fastfetch/logos/blizzard-$d-$pal.webp"
  done
done
echo "done"
shopt -s nullglob
logos=("$HOME/.local/share/fastfetch/logos/"*.webp)
echo "${#logos[@]}"
