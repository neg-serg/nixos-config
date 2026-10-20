#!/usr/bin/env bash
# audio-cpp-models.sh -- fetch the Audio Flamingo Next GGUF used by audio.cpp.
#
# Audio Flamingo Next is the newest model of the Flamingo family (Audio
# Flamingo 3 -> Next): speech, environmental sound and music understanding in
# one audio-language model.  Through audio.cpp it runs on the GPU over Vulkan
# (RADV on this host) — the ROCm torch path cannot hold an 8B model in 17 GB
# and never finishes the device move (see local-music-ai.md), while this path
# produced a 120-token description of a two-minute clip in 4.4 s.
#
# Usage:
#   audio-cpp-models.sh [--dir DIR] [--check] [--dry-run]
#
#   --dir DIR    model directory (default: /zero/ai/music-ai/audio-cpp)
#   --check      report whether the file is present, change nothing;
#                exit 1 when it is missing
#   --dry-run    print the download command, change nothing
#
# Notes:
#   * One file, pinned by size and sha256; a download that does not match is
#     discarded, so a half-written file can never be mistaken for the model.
#   * Resumable: curl --continue-at - picks up where an interrupted run left
#     off (the 8.7 GiB download did get cut once on this link).
#   * Writes only inside --dir; / and an empty path are refused.
#
# Exit codes: 0 ok, 1 download failed or the file is missing, 2 bad usage.
set -euo pipefail

DEFAULT_DIR="/zero/ai/music-ai/audio-cpp"
FILE="audio-flamingo-next-q8_0.gguf"
SIZE=9312869120
SHA256="124969625d2bd14af1a732de58ca53c2711fdb68e02f5504d408ccf637f1eb0a"
URL="https://huggingface.co/audio-cpp/Audio-Flamingo-GGUF/resolve/main/$FILE"

MODE="apply"
DIR="$DEFAULT_DIR"

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      DIR="${2:?--dir needs a path}"
      shift 2
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --dry-run)
      MODE="dry"
      shift
      ;;
    -h | --help) usage 0 ;;
    -*)
      echo "unknown option: $1" >&2
      usage 2
      ;;
    *)
      echo "unexpected argument: $1" >&2
      usage 2
      ;;
  esac
done

# Refuse the paths a bad --dir could turn into. pwd -P resolves symlinks, so a
# link pointing at / is caught as well.
case "$DIR" in
  "" | "/")
    echo "audio-cpp-models: refusing to use '$DIR' as the model directory" >&2
    exit 2
    ;;
esac
mkdir -p "$DIR" 2> /dev/null || true
if [[ -d "$DIR" ]]; then
  RESOLVED="$(cd "$DIR" && pwd -P)"
  [[ "$RESOLVED" == "/" ]] && {
    echo "audio-cpp-models: refusing to write into /" >&2
    exit 2
  }
  DIR="$RESOLVED"
fi
TARGET="$DIR/$FILE"

verify() {
  [[ -f "$TARGET" ]] || return 1
  local size
  size="$(stat -c %s "$TARGET")"
  [[ "$size" == "$SIZE" ]] || return 1
  [[ "$(sha256sum "$TARGET" | cut -d' ' -f1)" == "$SHA256" ]]
}

case "$MODE" in
  check)
    if verify; then
      echo "audio-cpp-models: $TARGET ($((SIZE / 1048576)) MB) present"
      exit 0
    fi
    if [[ -f "$TARGET" ]]; then
      echo "audio-cpp-models: $TARGET present but does not match size/sha256" >&2
    else
      echo "audio-cpp-models: $TARGET missing (run without --check)" >&2
    fi
    exit 1
    ;;
  dry)
    echo "would fetch $URL -> $TARGET ($((SIZE / 1048576)) MB, sha256 pinned)"
    exit 0
    ;;
esac

if verify; then
  echo "audio-cpp-models: $TARGET already in place"
  exit 0
fi

echo "audio-cpp-models: fetching $FILE ($((SIZE / 1048576)) MB) into $DIR"
curl -fL --retry 5 --retry-delay 5 --continue-at - -o "$TARGET.part" "$URL"
mv -f "$TARGET.part" "$TARGET"

if ! verify; then
  echo "audio-cpp-models: $TARGET failed the size/sha256 check, removing it" >&2
  rm -f "$TARGET"
  exit 1
fi
echo "audio-cpp-models: $TARGET ok"
