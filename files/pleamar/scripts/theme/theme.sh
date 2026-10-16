#!/usr/bin/env bash
# theme.sh — the pleamar theme pipeline: wallpaper (or an explicit colour) to
# ~/.config/pleamar/theme.plm.
#
# theme.plm is the writable half of the palette (INTERFACES.md §1.4): a scene
# imports it after lib/palette.plm and reads `skin.*` names, so the wallpaper's
# colours reach the widgets without touching the frozen palette. It is written
# here, never into the repo, and pleamar re-reads an imported file when it
# changes — rewriting the file re-themes the running scenes.
#
# The colours come from theme-extract.awk, a port of the two legacy samplers:
#
#   * tones    — the greeter's weighted k-means in Oklab (k=4), sorted by
#                lightness: the darkest cluster is `skin.coal`, the next
#                `skin.surface`, the lightest starts `skin.ink` (clamped to a
#                4.5:1 contrast on `skin.surface`);
#   * accent   — Helpers/AccentSampler.js's mean of the saturated pixels,
#                hue-matched onto colors.accent.primary (#006FCC) the way
#                Settings/Theme.qml derives Theme.accentPrimary.
#
# Usage and every option: --help. Run test.sh for the hermetic proof.
#
# Exit: 0 the file was written, 1 nothing to write or a bad input, 2 usage or
# missing-tool error.

set -euo pipefail

# readlink -f so a deployment that symlinks the script still finds its
# sibling theme-extract.awk.
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
TOOL_NAME="theme"

# Tools, overridable for tests and for a host with unusual names.
MAGICK_BIN="${MAGICK_BIN:-magick}"
AWK_BIN="${AWK_BIN:-awk}"
JQ_BIN="${JQ_BIN:-jq}"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
OUT="$CONFIG_HOME/pleamar/theme.plm"

# Palette values and where each came from; filled in below.
WALLPAPER=""
EXTRACTED=0
COAL=""
SURFACE=""
INK=""
ACCENT=""
COAL_NOTE=""
SURFACE_NOTE=""
INK_NOTE=""
ACCENT_NOTE=""

TMP_FILE=""
cleanup() {
  if [[ -n "$TMP_FILE" && -e "$TMP_FILE" ]]; then
    rm -f -- "$TMP_FILE"
  fi
  return 0
}
trap cleanup EXIT

err() { printf '%s: %s\n' "$TOOL_NAME" "$*" >&2; }
die() {
  err "$@"
  exit 1
}
usage_die() {
  err "$@"
  err "see --help"
  exit 2
}
tool_die() {
  err "$@"
  exit 2
}

usage() {
  cat << 'EOF'
theme.sh — build ~/.config/pleamar/theme.plm from the wallpaper.

Usage:
  theme.sh [--wallpaper FILE] [--accent '#RRGGBB'] [--from-json FILE]
  theme.sh --help

Where the wallpaper is found, in this order:
  --wallpaper FILE
  $XDG_CACHE_HOME/pleamar/wallpaper-path      (INTERFACES.md §1.2, first line)
  $XDG_CACHE_HOME/quickshell-wallpaper-path   (the legacy cache, first line)

What is written: ~/.config/pleamar/theme.plm, a strict `library Skin { … }`
with skin.coal/surface/ink/ink.dim/accent/accent.hover/accent.deep/on.accent.
Scenes import it after lib/palette.plm and read the skin.* names; copying one
into the repo is never needed. The file is replaced atomically (a temp file in
the same directory, then mv). Nothing else under ~/.config/pleamar is touched.

Colours:
  * tones come from a 48x48 ImageMagick sample of the wallpaper: weighted
    k-means in Oklab (the greeter's algorithm, k=4), darkest to lightest;
  * the accent is the legacy AccentSampler mean of the saturated pixels,
    hue-matched onto #006FCC (Settings/Theme.qml's accentPrimary);
  * --accent overrides the extracted accent; --from-json FILE reads a JSON
    object and overrides any of coal, surface, ink, accent that it gives
    ("#RRGGBB" strings, "#RGB" accepted). --accent wins over the file;
  * no wallpaper to sample and no colour given is an error — the file is left
    as it was. A colour given without a wallpaper keeps the QS base palette
    for the tones it did not name (colors.background #000000,
    colors.surfaceVariant #242A35, colors.text.primary #CBD6E5,
    colors.accent.primary #006FCC); skin.ink.dim stays the mix of the two
    text/surface tones above.

Environment: MAGICK_BIN (magick), AWK_BIN (awk), JQ_BIN (jq, --from-json only).

Exit: 0 written, 1 nothing to write or a bad input, 2 usage or missing tool.
EOF
}

# ---- arguments --------------------------------------------------------------

WALLPAPER_ARG=""
ACCENT_ARG=""
FROM_JSON=""

while (($# > 0)); do
  case "$1" in
    --wallpaper)
      (($# >= 2)) || usage_die "--wallpaper needs a FILE"
      WALLPAPER_ARG="$2"
      shift 2
      ;;
    --accent)
      (($# >= 2)) || usage_die "--accent needs a '#RRGGBB' value"
      ACCENT_ARG="$2"
      shift 2
      ;;
    --from-json)
      (($# >= 2)) || usage_die "--from-json needs a FILE"
      FROM_JSON="$2"
      shift 2
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      usage_die "unknown argument: $1"
      ;;
  esac
done

# "#abc" | "#aabbcc" (any case) -> "#aabbcc", else fail.
normalize_hex() {
  local value="${1,,}"
  if [[ "$value" =~ ^#[0-9a-f]{6}$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  if [[ "$value" =~ ^#[0-9a-f]{3}$ ]]; then
    printf '#%s%s%s%s%s%s' \
      "${value:1:1}" "${value:1:1}" "${value:2:1}" "${value:2:1}" \
      "${value:3:1}" "${value:3:1}"
    return 0
  fi
  return 1
}

# First non-empty line of a cache file, trimmed of surrounding whitespace
# (spaces inside a path stay).
read_path_file() {
  local file="$1" line
  [[ -f "$file" ]] || return 1
  line="$(head -n 1 -- "$file" 2> /dev/null || true)"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "$line" ]] || return 1
  printf '%s' "$line"
}

# ---- extraction -------------------------------------------------------------

extract_palette() {
  local wall="$1"
  command -v "$MAGICK_BIN" > /dev/null 2>&1 \
    || tool_die "no '$MAGICK_BIN' on PATH (MAGICK_BIN overrides it)"
  command -v "$AWK_BIN" > /dev/null 2>&1 \
    || tool_die "no '$AWK_BIN' on PATH (AWK_BIN overrides it)"
  # sRGB + 8 bit so every line carries a six-digit #RRGGBB; `!` keeps the
  # sample square whatever the wallpaper's aspect ratio is.
  "$MAGICK_BIN" "$wall" -auto-orient -colorspace sRGB -resize '48x48!' -alpha off -depth 8 txt:- \
    | "$AWK_BIN" -f "$SCRIPT_DIR/theme-extract.awk"
}

# Read `name=#rrggbb` lines into the palette variables. The caller checks the
# values; an unknown name is an extractor bug, not user input.
load_pairs() {
  local line key value
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      coal) COAL="$value" ;;
      surface) SURFACE="$value" ;;
      ink) INK="$value" ;;
      accent) ACCENT="$value" ;;
      *)
        err "extractor: unexpected key '$key'"
        return 1
        ;;
    esac
  done
}

# ---- resolve the wallpaper --------------------------------------------------

if [[ -n "$WALLPAPER_ARG" ]]; then
  WALLPAPER="$WALLPAPER_ARG"
  if [[ ! -r "$WALLPAPER" ]]; then
    die "--wallpaper: not a readable file: $WALLPAPER"
  fi
else
  for cache_file in "$CACHE_HOME/pleamar/wallpaper-path" "$CACHE_HOME/quickshell-wallpaper-path"; do
    if WALLPAPER="$(read_path_file "$cache_file")"; then
      break
    fi
    WALLPAPER=""
  done
fi

# ---- extract, then let explicit colours win --------------------------------

if [[ -n "$WALLPAPER" ]]; then
  if [[ -r "$WALLPAPER" ]]; then
    if extracted="$(extract_palette "$WALLPAPER")"; then
      if load_pairs <<< "$extracted"; then
        EXTRACTED=1
        for value in "$COAL" "$SURFACE" "$INK" "$ACCENT"; do
          if [[ ! "$value" =~ ^#[0-9a-f]{6}$ ]]; then
            die "extractor: bad value from '$WALLPAPER': $value"
          fi
        done
      fi
    else
      err "cannot sample '$WALLPAPER' (not a readable image?) — ignoring it"
    fi
  else
    err "wallpaper from the cache is gone: $WALLPAPER"
  fi
fi

# What each tone is, for the generated file's comments.
if ((EXTRACTED == 1)); then
  COAL_NOTE="colors.background role: the wallpaper's darkest Oklab k-means cluster."
  SURFACE_NOTE="colors.surfaceVariant role: the wallpaper's second-darkest cluster."
  INK_NOTE="colors.text.primary role: the lightest cluster, pushed to 4.5:1 contrast on skin.surface."
  ACCENT_NOTE="colors.accent.primary role: the wallpaper's mean saturated colour, hue-matched onto #006FCC (Settings/Theme.qml accentPrimary)."
else
  COAL_NOTE="colors.background, the QS fallback #ff000000 (opaque part): no wallpaper was sampled."
  SURFACE_NOTE="colors.surfaceVariant, the QS fallback #242A35: no wallpaper was sampled."
  INK_NOTE="colors.text.primary, the QS fallback #CBD6E5: no wallpaper was sampled."
  ACCENT_NOTE="colors.accent.primary, the QS fallback #006FCC: no wallpaper was sampled."
fi

if [[ -n "$FROM_JSON" ]]; then
  [[ -r "$FROM_JSON" ]] || die "--from-json: cannot read $FROM_JSON"
  command -v "$JQ_BIN" > /dev/null 2>&1 \
    || tool_die "no '$JQ_BIN' on PATH (JQ_BIN overrides it); jq is needed for --from-json"
  json_keys=0
  for key in coal surface ink accent; do
    value="$("$JQ_BIN" -er --arg k "$key" '.[$k] | select(type == "string")' "$FROM_JSON" 2> /dev/null || true)"
    [[ -n "$value" ]] || continue
    normalized="$(normalize_hex "$value")" \
      || die "--from-json: $key is not a '#RRGGBB' colour: $value"
    case "$key" in
      coal)
        COAL="$normalized"
        COAL_NOTE="--from-json $FROM_JSON (overrides the sampled tone)."
        ;;
      surface)
        SURFACE="$normalized"
        SURFACE_NOTE="--from-json $FROM_JSON (overrides the sampled tone)."
        ;;
      ink)
        INK="$normalized"
        INK_NOTE="--from-json $FROM_JSON (overrides the sampled tone)."
        ;;
      accent)
        ACCENT="$normalized"
        ACCENT_NOTE="--from-json $FROM_JSON (overrides the sampled accent)."
        ;;
    esac
    json_keys=$((json_keys + 1))
  done
  ((json_keys > 0)) \
    || die "--from-json: no coal/surface/ink/accent string in $FROM_JSON"
fi

if [[ -n "$ACCENT_ARG" ]]; then
  normalized="$(normalize_hex "$ACCENT_ARG")" \
    || die "--accent: not a '#RRGGBB' colour: $ACCENT_ARG"
  ACCENT="$normalized"
  if ((EXTRACTED == 1)); then
    ACCENT_NOTE="--accent (overrides the sampled accent)."
  else
    ACCENT_NOTE="--accent (no wallpaper was sampled)."
  fi
fi

if [[ -z "$COAL$SURFACE$INK$ACCENT" ]]; then
  err "nothing to extract: no wallpaper found and no --accent/--from-json colour"
  err "looked at: $CACHE_HOME/pleamar/wallpaper-path, $CACHE_HOME/quickshell-wallpaper-path"
  err "pass --wallpaper FILE, --accent '#RRGGBB' or --from-json FILE"
  exit 1
fi

# Fallbacks for tones an explicit colour did not name.
COAL="${COAL:-#000000}"
SURFACE="${SURFACE:-#242A35}"
INK="${INK:-#CBD6E5}"
ACCENT="${ACCENT:-#006FCC}"

# ---- write ------------------------------------------------------------------

render() {
  if [[ -n "$WALLPAPER" ]]; then
    source_line="$WALLPAPER"
  else
    source_line="none (explicit colours only)"
  fi
  printf '// theme.plm — the wallpaper palette, generated by\n'
  printf '// files/pleamar/scripts/theme/theme.sh. Edits here are overwritten.\n'
  printf '//\n'
  printf '// source:  %s\n' "$source_line"
  printf '// written: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '//\n'
  printf '// Import it after the palette (INTERFACES.md §1.4) and read skin.* names:\n'
  printf '//\n'
  printf '//   import "../../lib/palette.plm"\n'
  printf '//   import "../../theme.plm"\n'
  printf '//\n'
  printf '// It declares no name palette.plm declares, so nothing in the shell changes\n'
  printf '// meaning when a scene opts in; a rewritten import re-themes a running scene.\n'
  printf '\n'
  printf 'library Skin strict {\n'
  printf '\n'
  printf '    // %s\n' "$COAL_NOTE"
  printf '    let skin.coal = %s\n' "$COAL"
  printf '\n'
  printf '    // %s\n' "$SURFACE_NOTE"
  printf '    let skin.surface = %s\n' "$SURFACE"
  printf '\n'
  printf '    // %s\n' "$INK_NOTE"
  printf '    let skin.ink = %s\n' "$INK"
  printf '\n'
  printf '    // colors.text.secondary role: skin.ink mixed 35%% toward skin.surface —\n'
  printf '    // the formula follows whatever ink/surface this file holds.\n'
  printf '    let skin.ink.dim = mix(skin.ink, skin.surface, 35%%)\n'
  printf '\n'
  printf '    // %s\n' "$ACCENT_NOTE"
  printf '    let skin.accent = %s\n' "$ACCENT"
  printf '    // Theme.accentHover: towardsWhite(accentPrimary, 0.2).\n'
  printf '    let skin.accent.hover = mix(skin.accent, #ffffff, 20%%)\n'
  printf '    // Theme.accentDarkStrong: towardsBlack(accentPrimary, 0.8).\n'
  printf '    let skin.accent.deep = mix(skin.accent, skin.coal, 80%%)\n'
  printf '    // colors.onAccent, unchanged.\n'
  printf '    let skin.on.accent = #ffffff\n'
  printf '}\n'
}

out_dir="$(dirname -- "$OUT")"
mkdir -p -- "$out_dir"
TMP_FILE="$(mktemp --tmpdir="$out_dir" .theme.plm.XXXXXX)"
render > "$TMP_FILE"
chmod 0644 "$TMP_FILE"
mv -f -- "$TMP_FILE" "$OUT"
TMP_FILE=""

printf '%s: wrote %s\n' "$TOOL_NAME" "$OUT"
if [[ -n "$WALLPAPER" ]]; then
  printf '%s: source %s\n' "$TOOL_NAME" "$WALLPAPER"
fi
printf '%s: coal %s  surface %s  ink %s  accent %s\n' \
  "$TOOL_NAME" "$COAL" "$SURFACE" "$INK" "$ACCENT"
