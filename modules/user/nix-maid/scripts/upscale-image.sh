#!/usr/bin/env bash
# upscale-image — AI image upscaler on odin (real-ESRGAN via Vulkan ncnn).
#
# Thin wrapper around realesrgan-ncnn-vulkan (GPU, RX 9070 XT) with the
# model naming used elsewhere on this host:
#   realesrgan-x4plus        — general-purpose 4x (default)
#   realesrgan-x4plus-anime  — anime-tuned 4x (--anime)
#
# Usage:
#   upscale-image FILE... [options]        single/multiple files
#   upscale-image DIR [options]            batch: every image in DIR
#   Options:
#     --anime     use the anime-tuned model
#     -o OUT      output file (single input) or directory (batch)
#   Outputs default to <stem>_x4.png next to the input; for a batch of DIR
#   the default is DIR_x4/ in the parent of DIR.
set -euo pipefail

MODEL_GEN="realesrgan-x4plus"
MODEL_ANIME="realesrgan-x4plus-anime"
SCALE=4

command -v realesrgan-ncnn-vulkan >/dev/null || { echo "upscale-image: realesrgan-ncnn-vulkan not found" >&2; exit 3; }

model="$MODEL_GEN"
out_opt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anime) model="$MODEL_ANIME"; shift ;;
    -o|--out) out_opt="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "upscale-image: unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "upscale-image: no inputs" >&2; exit 2; }

is_image() { case "$1" in *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.tif|*.tiff) return 0;; *) return 1;; esac; }

upscale_file() {
  local in out stem dir
  in="$(readlink -f "$1")"
  [ -f "$in" ] || { echo "upscale-image: not a file: $in" >&2; return 1; }
  if [ -n "$out_opt" ]; then out="$(readlink -f "$out_opt")"; else
    stem="$(basename "$in" | sed 's/\.[^.]*$//')"
    dir="$(dirname "$in")"
    out="$dir/$stem"_x4.png
  fi
  [ "$in" = "$out" ] && { echo "upscale-image: input == output, refusing" >&2; return 1; }
  echo "[upscale-image] $in -> $out ($model x$SCALE)"
  realesrgan-ncnn-vulkan -i "$in" -o "$out" -n "$model" -s "$SCALE"
}

if [ -d "$1" ]; then
  in_dir="$(readlink -f "$1")"
  if [ -n "$out_opt" ]; then out_dir="$(readlink -f "$out_opt")"; else
    out_dir="$(dirname "$in_dir")/$(basename "$in_dir")"_x4
  fi
  mkdir -p "$out_dir"
  echo "[upscale-image] batch: $in_dir/* -> $out_dir/ ($model x$SCALE)"
  realesrgan-ncnn-vulkan -i "$in_dir" -o "$out_dir" -n "$model" -s "$SCALE"
  echo "[upscale-image] done: $out_dir" >&2
else
  fail=0
  for f in "$@"; do upscale_file "$f" || fail=1; done
  exit $fail
fi
