#!/usr/bin/env bash
# Regenerate files/gui/mango/Display-P3.icc with lcms2.
# Run from the repo root:
#   nix shell nixpkgs#gcc nixpkgs#lcms2 -c bash files/gui/mango/generate-display-p3.sh
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
mapfile -t lcms_flags < <(pkg-config --cflags --libs lcms2)
cc -o /tmp/gen-display-p3 "$dir/generate-display-p3.c" "${lcms_flags[@]}" -lm
/tmp/gen-display-p3 "$dir/Display-P3.icc"
