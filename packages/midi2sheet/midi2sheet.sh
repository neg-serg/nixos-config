#!/usr/bin/env bash
# midi2sheet: MIDI -> sheet music PDF (piano grand staff).
#
# Splits the input into treble/bass hands by pitch, engraves the result with
# headless MuseScore (under Xvfb) and exports a PDF. Optionally also keeps the
# editable MuseScore source (.mscz).
#
# Usage:
#   midi2sheet INPUT.mid [-o OUT.pdf] [--mscz] [--split N]
#
# The score title comes from the input file name (extension stripped).
set -euo pipefail

usage() {
  echo "usage: midi2sheet INPUT.mid [-o OUT.pdf] [--mscz] [--split N]" >&2
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
IN="$1"
shift
[ -f "$IN" ] || {
  echo "midi2sheet: no such file: $IN" >&2
  exit 2
}

OUT=""
KEEP_MSCZ=0
SPLIT=60
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      OUT="$2"
      shift 2
      ;;
    --mscz)
      KEEP_MSCZ=1
      shift
      ;;
    --split)
      SPLIT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "midi2sheet: unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$IN" in
  *.mid | *.midi) STEM="${IN%.*}" ;;
  *) STEM="$IN" ;;
esac
[ -n "$OUT" ] || OUT="${STEM}.pdf"
MSCZ_OUT="${STEM}.mscz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# MuseScore derives the score title from the input file name on MIDI import,
# so export to mscz first, rewrite the workTitle metaTag, then render the PDF.
SPLIT_MID="$TMP/$(basename "$STEM").mid"
WORK="$TMP/work.mscz"
TITLE="$(basename "$STEM")"

"${PYTHON:-python3}" "$LIB/split.py" "$IN" "$SPLIT_MID" --threshold "$SPLIT"
xvfb-run -a musescore "$SPLIT_MID" -o "$WORK"
"${PYTHON:-python3}" "$LIB/patch_title.py" "$WORK" "$TITLE"
xvfb-run -a musescore "$WORK" -o "$OUT"
if [ "$KEEP_MSCZ" -eq 1 ]; then
  cp "$WORK" "$MSCZ_OUT"
fi
echo "midi2sheet: wrote $OUT"
[ "$KEEP_MSCZ" -eq 1 ] && echo "midi2sheet: wrote $MSCZ_OUT"
