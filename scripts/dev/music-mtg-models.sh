#!/usr/bin/env bash
# music-mtg-models.sh -- fetch the pre-trained MTG/Essentia music taggers
# (EffNet-Discogs backbone plus the trained classification heads) used by the
# music-* wrappers, as a complement to the zero-shot CLAP tags.
#
# The canonical download host (essentia.upf.edu) is unreachable from this
# network, so every file is fetched from a byte-identical mirror that was
# verified against the upstream copy (size + sha256).  The heads are the
# classic open taggers trained on Discogs and MTG-Jamendo:
#
#   core  EffNet-Discogs backbone, genre_discogs400 (400 Discogs styles),
#         mtg_jamendo_moodtheme (56 mood/theme tags),
#         mtg_jamendo_instrument (40 instruments)          ~26 MB
#   all   core + danceability, voice/instrumental and the six single-mood
#         heads (aggressive/electronic/happy/party/relaxed/sad) ~32 MB
#
# Usage:
#   music-mtg-models.sh [--dir DIR] [--set core|all] [--check] [--dry-run]
#
#   --dir DIR    model directory (default: /zero/ai/music-ai/mtg-models)
#   --set NAME   core (default) or all
#   --check      list models present/missing, change nothing; exit 1 when a
#                file of the selected set is missing
#   --dry-run    print what would be downloaded, change nothing
#
# Notes:
#   * Writes only inside --dir (fixed file names from the manifest below);
#     --dir is resolved with pwd -P and / (or an empty path) is refused, so
#     the script cannot be tricked into writing elsewhere.
#   * No sudo, no virtualenv access: it downloads, size/sha256-checks and
#     renames into place.
#   * Every download uses curl -fL --retry; a file is only accepted after the
#     size and sha256 match the pinned value.  When a mirror dies, the next
#     source for the same file is tried.
#
# Exit codes: 0 ok, 1 download failed or --check found missing files,
# 2 bad usage.
set -euo pipefail

DEFAULT_DIR="/zero/ai/music-ai/mtg-models"
DIR="$DEFAULT_DIR"
SET_NAME="core"
MODE="install"
DRY_RUN=0
DIR_REAL=""
CUR_TMP=""

# Manifest: name|set|size|sha256|purpose|url1 url2 ...
# All URLs of one entry must serve the exact same bytes.
manifest() {
  cat << 'MANIFEST'
discogs-effnet-bs64-1.pb|core|18366619|3ed9af50d5367c0b9c795b294b00e7599e4943244f4cbd376869f3bfc87721b1|EffNet-Discogs backbone (1280-d embeddings, 16 kHz)|https://raw.githubusercontent.com/bmai1/museko/main/apps/web/essentia_model/discogs-effnet-bs64-1.pb https://raw.githubusercontent.com/AMAAI-Lab/mirflex/main/essentia_models/discogs-effnet-bs64-1.pb
genre_discogs400-discogs-effnet-1.pb|core|2057977|3885ba078a35249af94b8e5e4247689afac40deca4401a4bc888daf5a579c01c|400 Discogs style labels|https://raw.githubusercontent.com/bmai1/museko/main/apps/web/essentia_model/genre_discogs400-discogs-effnet-1.pb https://raw.githubusercontent.com/YatingMusic/MusiConGen/main/preproc/3_tags/essentia/genre_discogs400-discogs-effnet-1.pb
genre_discogs400-discogs-effnet-1.json|core|14950|1cc9c6a9b123914b4ce96f7205450d4f69b50b7755ebeb8de93d79a7cb43582c|Discogs400 class names|https://raw.githubusercontent.com/bmai1/museko/main/apps/web/essentia_model/genre_discogs400-discogs-effnet-1.json
mtg_jamendo_moodtheme-discogs-effnet-1.pb|core|2739668|03f2b047020aee4ab39f8880da7bdae2a36d06a1508d656c6d424ad4d6de07a9|56 MTG-Jamendo mood/theme tags|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mtg_jamendo_moodtheme-discogs-effnet-1.pb https://raw.githubusercontent.com/AMAAI-Lab/mirflex/main/essentia_models/mtg_jamendo_moodtheme-discogs-effnet-1.pb
mtg_jamendo_moodtheme-discogs-effnet-1.json|core|3646|d62cd90263e4d613fa7fcce7a831e339450394794af63685f96e065c1a896ab0|mood/theme class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mtg_jamendo_moodtheme-discogs-effnet-1.json https://raw.githubusercontent.com/AMAAI-Lab/mirflex/main/essentia_models/mtg_jamendo_moodtheme-discogs-effnet-1.json
mtg_jamendo_instrument-discogs-effnet-1.pb|core|2706836|2e8c3003c722e098da371b6a1f7ad0ce62fac0dcfc09c7c7997d430941196c2a|40 MTG-Jamendo instruments|https://raw.githubusercontent.com/AMAAI-Lab/mirflex/main/essentia_models/mtg_jamendo_instrument-discogs-effnet-1.pb https://web.archive.org/web/20240722092456id_/https://essentia.upf.edu/models/classification-heads/mtg_jamendo_instrument/mtg_jamendo_instrument-discogs-effnet-1.pb
mtg_jamendo_instrument-discogs-effnet-1.json|core|3382|7d02204c6451b5615e2968ec6364bbae3b915c886e608f05f00d3a38dc5177c4|instrument class names|https://raw.githubusercontent.com/AMAAI-Lab/mirflex/main/essentia_models/mtg_jamendo_instrument-discogs-effnet-1.json https://web.archive.org/web/20240722092456id_/https://essentia.upf.edu/models/classification-heads/mtg_jamendo_instrument/mtg_jamendo_instrument-discogs-effnet-1.json
danceability-discogs-effnet-1.pb|all|514458|e1251f02cdc846445e2bc1fb3fe9963e32728c5c000e009188ae47c8963cb4c4|danceable / not_danceable|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/danceability-discogs-effnet-1.pb
danceability-discogs-effnet-1.json|all|1989|589e61dc05f0d7935be4b5fa7ab4341e5dc7cfecc6898f83503558564790cd75|danceability class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/danceability-discogs-effnet-1.json
voice_instrumental-discogs-effnet-1.pb|all|514458|c8033548e17c292874265db62e82a051247768d10375a35a769e7bf695f16acf|voice / instrumental|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/voice_instrumental-discogs-effnet-1.pb https://raw.githubusercontent.com/AMAAI-Lab/mirflex/main/essentia_models/voice_instrumental-discogs-effnet-1.pb
voice_instrumental-discogs-effnet-1.json|all|2013|43ac2c3b055dfaed20f6232e0f10636c287f1c5a6e5bd02c5585860031964c8f|voice/instrumental class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/voice_instrumental-discogs-effnet-1.json
mood_aggressive-discogs-effnet-1.pb|all|514458|7705284e3a67f23f04d3f2fd75e18a82c0e70db8875b7b6f7061f2432de80858|aggressive mood score|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_aggressive-discogs-effnet-1.pb
mood_aggressive-discogs-effnet-1.json|all|2386|81773e95d78db1b93283d73b2d06344d1ff79685b57d9428a40d47fdfcf537b8|aggressive class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_aggressive-discogs-effnet-1.json
mood_electronic-discogs-effnet-1.pb|all|514458|74cb244069c3803d86e6ee7c2817ecac46e37ac2759c457fa2f20d2132a8cb8b|electronic mood score|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_electronic-discogs-effnet-1.pb
mood_electronic-discogs-effnet-1.json|all|2394|150c21220b7f383868b60e495163498dbabfc4f73d4d1804f525ef352f2897b9|electronic class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_electronic-discogs-effnet-1.json
mood_happy-discogs-effnet-1.pb|all|514458|de322aee7f4da29ecbd149c86e7964bd6fabe41ca85698a0be40a39d49e88633|happy mood score|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_happy-discogs-effnet-1.pb
mood_happy-discogs-effnet-1.json|all|2350|ed4601bc396b23367d29cf45aa327366cdfdbd3e2baeb7a3f7893237f1ffd9e6|happy class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_happy-discogs-effnet-1.json
mood_party-discogs-effnet-1.pb|all|514458|bbd773a27002978179dd6fc5ffb75b7c41e6a7e412b5c5254d51a025e5b9373e|party mood score|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_party-discogs-effnet-1.pb
mood_party-discogs-effnet-1.json|all|2350|a7f15c6e05db7c3e9226646a87162ebb9cc00aea8bdbbc910aedafa7f4a8fdfb|party class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_party-discogs-effnet-1.json
mood_relaxed-discogs-effnet-1.pb|all|514458|2c5aa6666b58fe80429a2dc677a135e9995922889b5a399af87d1c15f0ebb71d|relaxed mood score|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_relaxed-discogs-effnet-1.pb
mood_relaxed-discogs-effnet-1.json|all|2364|86c0fe1c2c6d49bf08537bc2d3a602204feaede011ed119c1fc6c36270f60e6a|relaxed class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_relaxed-discogs-effnet-1.json
mood_sad-discogs-effnet-1.pb|all|514458|4865cba49968b6ec295db3e8af6b4a7bb506b1a646628b9f07ee9910d52df82c|sad mood score|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_sad-discogs-effnet-1.pb
mood_sad-discogs-effnet-1.json|all|2334|7f2c00099ad8255af33e43ab77d1ac2c86a1dd9f46d3e5ea2a9a52246f5033d9|sad class names|https://raw.githubusercontent.com/benjyb1/DJMate/main/models/mood_sad-discogs-effnet-1.json
MANIFEST
}

usage() {
  awk 'NR > 1 && /^set -euo pipefail/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
  exit "${1:-0}"
}

info() { printf '%s\n' "$*"; }

die() {
  printf '%s: error: %s\n' "${0##*/}" "$*" >&2
  exit 1
}

die_usage() {
  printf '%s: error: %s\n' "${0##*/}" "$*" >&2
  exit 2
}

cleanup() {
  if [[ -n "$CUR_TMP" && -e "$CUR_TMP" ]]; then
    rm -f -- "$CUR_TMP"
  fi
}
trap cleanup EXIT

human_bytes() {
  awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1048576 }'
}

entry_wanted() {
  if [[ "$SET_NAME" == "all" ]]; then
    return 0
  fi
  [[ "$1" == "$SET_NAME" ]]
}

# Which entry sizes add up to the selected set (used for the summary lines).
set_totals() {
  local name entry_set size sha purpose urls
  local -n _total="$1" _count="$2"
  _total=0
  _count=0
  while IFS='|' read -r name entry_set size sha purpose urls; do
    [[ -n "$name" ]] || continue
    entry_wanted "$entry_set" || continue
    _total=$((_total + size))
    _count=$((_count + 1))
  done < <(manifest)
}

# Verify a file against the pinned size and sha256 (sha optional to skip).
verify_file() {
  local path="$1" want_size="$2" want_sha="$3" got_size got_sha
  [[ -f "$path" ]] || return 1
  got_size=$(stat -c %s -- "$path" 2> /dev/null) || return 1
  [[ "$got_size" == "$want_size" ]] || return 1
  if [[ -n "$want_sha" ]] && command -v sha256sum > /dev/null 2>&1; then
    got_sha=$(sha256sum -- "$path" | cut -d' ' -f1)
    [[ "$got_sha" == "$want_sha" ]] || return 1
  fi
  return 0
}

# Resolve --dir and refuse paths that cannot be a safe model directory.
ensure_dir() {
  [[ -n "$DIR" ]] || die "--dir must not be empty"
  [[ "$DIR" != "/" ]] || die "refusing to use / as the model directory"
  if [[ -e "$DIR" && ! -d "$DIR" ]]; then
    die "--dir is not a directory: $DIR"
  fi
  mkdir -p -- "$DIR"
  DIR_REAL=$(cd -- "$DIR" && pwd -P)
  [[ -n "$DIR_REAL" && "$DIR_REAL" != "/" ]] || die "refusing to use '$DIR_REAL' as the model directory"
}

# Turn a manifest file name into an absolute path inside DIR_REAL.
safe_target() {
  local name="$1" target
  case "$name" in
    "" | "." | ".." | */*) die "refusing unsafe file name: '$name'" ;;
  esac
  target="$DIR_REAL/$name"
  case "$target" in
    "$DIR_REAL"/*) ;;
    *) die "refusing to write outside $DIR_REAL: $target" ;;
  esac
  printf '%s\n' "$target"
}

do_check() {
  local name entry_set size sha purpose urls target present=0 total=0 count=0
  info "[check] $DIR (set: $SET_NAME)"
  while IFS='|' read -r name entry_set size sha purpose urls; do
    [[ -n "$name" ]] || continue
    entry_wanted "$entry_set" || continue
    count=$((count + 1))
    total=$((total + size))
    target="$DIR/$name"
    if verify_file "$target" "$size" "$sha"; then
      present=$((present + 1))
      printf '  %-7s %-52s %s\n' "ok" "$name" "$purpose"
    else
      printf '  %-7s %-52s %s\n' "MISSING" "$name" "$purpose"
    fi
  done < <(manifest)
  info "$present/$count files present; $(human_bytes "$total") expected in $DIR"
  [[ "$present" -eq "$count" ]]
}

fetch_one() {
  local name="$1" want_size="$2" want_sha="$3" urls="$4" target url
  local url_list=()
  target=$(safe_target "$name")
  if verify_file "$target" "$want_size" "$want_sha"; then
    info "  ok       $name"
    return 0
  fi
  read -r -a url_list <<< "$urls"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    for url in "${url_list[@]}"; do
      info "  [dry-run] curl -fL --retry 3 -o $target '$url'"
    done
    return 0
  fi
  CUR_TMP="$DIR_REAL/.$name.part.$$"
  for url in "${url_list[@]}"; do
    info "  fetch    $name"
    info "           <- $url"
    if curl -fL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 20 --max-time 900 -o "$CUR_TMP" "$url"; then
      if verify_file "$CUR_TMP" "$want_size" "$want_sha"; then
        mv -f -- "$CUR_TMP" "$target"
        CUR_TMP=""
        info "  done     $name ($(human_bytes "$want_size"))"
        return 0
      fi
      info "  bad      $name: size/sha256 mismatch from that mirror"
    else
      info "  failed   $name: download error from that mirror"
    fi
    rm -f -- "$CUR_TMP"
  done
  CUR_TMP=""
  die "could not fetch $name from any mirror"
}

do_install() {
  local name entry_set size sha purpose urls total=0 count=0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    [[ -n "$DIR" ]] || die "--dir must not be empty"
    [[ "$DIR" != "/" ]] || die "refusing to use / as the model directory"
    DIR_REAL="${DIR%/}"
  else
    ensure_dir
  fi
  set_totals total count
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] $DIR_REAL (set: $SET_NAME, $count files, $(human_bytes "$total"))"
  else
    info "[install] $DIR_REAL (set: $SET_NAME, $count files, $(human_bytes "$total"))"
  fi
  while IFS='|' read -r name entry_set size sha purpose urls; do
    [[ -n "$name" ]] || continue
    entry_wanted "$entry_set" || continue
    fetch_one "$name" "$size" "$sha" "$urls"
  done < <(manifest)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] nothing was written"
  else
    info "done: $count files, $(human_bytes "$total"), in $DIR_REAL"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || usage 2
      DIR="$2"
      shift 2
      ;;
    --dir=*)
      DIR="${1#--dir=}"
      shift
      ;;
    --set)
      [[ $# -ge 2 ]] || usage 2
      SET_NAME="$2"
      shift 2
      ;;
    --set=*)
      SET_NAME="${1#--set=}"
      shift
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die_usage "unknown option: $1"
      ;;
    *)
      die_usage "unexpected argument: $1"
      ;;
  esac
done

case "$SET_NAME" in
  core | all) ;;
  *) die_usage "--set must be core or all (got: $SET_NAME)" ;;
esac

case "$MODE" in
  check) do_check ;;
  install) do_install ;;
  *) die "internal error: unknown mode $MODE" ;;
esac
