#!/usr/bin/env bash
# Refresh the derived music state in one pass: MERT similarity index, MTG tags
# and the mood/genre playlists that come out of them.
#
# Designed for the weekly autoIndex timer (modules/media/audio/music-tagging.nix),
# but it is a normal command too: every step is incremental, so a run over an
# unchanged library costs seconds.
#
# Usage:
#   music-refresh.sh [--index-args "ARGS"] [--tags-file FILE] [--playlists DIR]
#                    [--by GROUPS] [--music-dir DIR] [--min-score X]
#                    [--per-list N] [--skip-tags] [--skip-playlists]
#                    [--check] [--dry-run]
#
#   --index-args     extra arguments for music-index (quoted string; the timer
#                    passes the configured --layer/--threads/--limit here)
#   --tags-file      MTG tag JSONL (default ~/.cache/music-mtg/tags.jsonl)
#   --playlists      playlist directory (default ~/.config/mpd/playlists)
#   --by             label groups for the playlists (default "mood,parent")
#   --music-dir      library root (default ~/music)
#   --min-score      playlist score floor (default 0.15)
#   --per-list       tracks per playlist (default 120)
#   --skip-tags      only refresh the index (and playlists from existing tags)
#   --skip-playlists skip playlist generation
#   --check          report which tools exist and what would run, change nothing
#   --dry-run        print the commands without running them
#
# Exit codes: 0 all steps ok, 1 a step failed, 2 bad usage.
set -euo pipefail

INDEX_ARGS=""
TAGS_FILE="${MUSIC_MTG_TAGS:-$HOME/.cache/music-mtg/tags.jsonl}"
PLAYLISTS="$HOME/.config/mpd/playlists"
BY="mood,parent"
MUSIC_DIR="${MUSIC_DIR:-$HOME/music}"
MIN_SCORE="0.15"
PER_LIST="120"
SKIP_TAGS=""
SKIP_PLAYLISTS=""
MODE="apply"

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-args)
      INDEX_ARGS="${2:?--index-args needs a value}"
      shift 2
      ;;
    --tags-file)
      TAGS_FILE="${2:?--tags-file needs a path}"
      shift 2
      ;;
    --playlists)
      PLAYLISTS="${2:?--playlists needs a directory}"
      shift 2
      ;;
    --by)
      BY="${2:?--by needs a value}"
      shift 2
      ;;
    --music-dir)
      MUSIC_DIR="${2:?--music-dir needs a path}"
      shift 2
      ;;
    --min-score)
      MIN_SCORE="${2:?--min-score needs a number}"
      shift 2
      ;;
    --per-list)
      PER_LIST="${2:?--per-list needs a number}"
      shift 2
      ;;
    --skip-tags)
      SKIP_TAGS=1
      shift
      ;;
    --skip-playlists)
      SKIP_PLAYLISTS=1
      shift
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

# Wrappers are rendered by nix-maid into ~/.local/bin; fall back to PATH so the
# script also works from a plain shell.
resolve_tool() {
  local tool="$1"
  if [[ -x "$HOME/.local/bin/$tool" ]]; then
    printf '%s\n' "$HOME/.local/bin/$tool"
  elif command -v "$tool" > /dev/null 2>&1; then
    command -v "$tool"
  else
    return 1
  fi
}

steps=()
if index_tool="$(resolve_tool music-index)"; then
  # shellcheck disable=SC2206  # word splitting is intended for the arg string
  steps+=("index:$index_tool $INDEX_ARGS")
else
  steps+=("index:MISSING")
fi
if [[ -z "$SKIP_TAGS" ]]; then
  if tag_tool="$(resolve_tool music-mtg-tags)"; then
    steps+=("tags:$tag_tool --dir $MUSIC_DIR --out $TAGS_FILE --quiet")
  else
    steps+=("tags:MISSING")
  fi
fi
if [[ -z "$SKIP_PLAYLISTS" ]]; then
  if tag_tool="$(resolve_tool music-mtg-tags)"; then
    # --by takes one group per run, so a comma list becomes one step each
    # (mood and parent lists land side by side in the playlist directory).
    IFS=',' read -r -a groups <<< "$BY"
    for group in "${groups[@]}"; do
      group="${group// /}"
      [[ -n "$group" ]] || continue
      steps+=("playlists-$group:$tag_tool --tags $TAGS_FILE --playlists $PLAYLISTS --music-dir $MUSIC_DIR --by $group --min-score $MIN_SCORE --per-list $PER_LIST")
    done
  else
    steps+=("playlists:MISSING")
  fi
fi

echo "music-refresh: music_dir=$MUSIC_DIR tags=$TAGS_FILE playlists=$PLAYLISTS"
for step in "${steps[@]}"; do
  echo "  ${step%%:*} -> ${step#*:}"
done

if [[ "$MODE" == "check" ]]; then
  for step in "${steps[@]}"; do
    [[ "${step#*:}" == "MISSING" ]] && exit 1
  done
  echo "music-refresh: all tools present"
  exit 0
fi

if [[ "$MODE" == "dry" ]]; then
  exit 0
fi

failed=0
for step in "${steps[@]}"; do
  name="${step%%:*}"
  command="${step#*:}"
  if [[ "$command" == "MISSING" ]]; then
    echo "music-refresh: $name tool not found, skipping" >&2
    failed=1
    continue
  fi
  echo "music-refresh: $name"
  # The tool list was built with plain string concatenation, so run it through
  # the shell to honour the quoted --index-args.
  if ! bash -c "$command"; then
    echo "music-refresh: $name failed" >&2
    failed=1
  fi
done
exit "$failed"
