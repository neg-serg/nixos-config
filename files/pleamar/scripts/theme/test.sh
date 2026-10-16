#!/usr/bin/env bash
# test.sh — hermetic proof for theme.sh: fixture wallpapers, a throwaway
# HOME/XDG tree, assertions on the generated theme.plm, and (when the compiler
# is available) a /tmp consumer compile that imports the generated file.
#
# Nothing here touches the developer's real ~/.config: every run gets a fresh
# `mktemp -d`. The fixtures are drawn with ImageMagick, so the run needs no
# network and no wallpaper collection.
#
# Usage: test.sh [--keep] [--pleamar FILE]
# Environment: PLEAMAR_BIN (default: pleamar) — the compiler to compile the
# consumer with; a missing binary is a skip notice, not a failure. PASS
# `--pleamar /path/to/pleamar` for a binary outside PATH.
#
# Exit: 0 every assertion passed (a skipped compiler counts as a pass), 1 an
# assertion failed, 2 a missing tool or a usage error.

set -euo pipefail

# readlink -f so a deployment that symlinks the script still finds its
# sibling theme-extract.awk.
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
THEME_SH="$SCRIPT_DIR/theme.sh"
TOOL_NAME="theme-test"

MAGICK_BIN="${MAGICK_BIN:-magick}"
PLEAMAR_BIN="${PLEAMAR_BIN:-pleamar}"

KEEP=0
FAILURES=0
WORK=""

cleanup() {
  if ((KEEP == 0)) && [[ -n "$WORK" && -d "$WORK" ]]; then
    rm -rf -- "$WORK"
  fi
  return 0
}
trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --keep)
      KEEP=1
      shift
      ;;
    --pleamar)
      (($# >= 2)) || {
        printf '%s: --pleamar needs a FILE\n' "$TOOL_NAME" >&2
        exit 2
      }
      PLEAMAR_BIN="$2"
      shift 2
      ;;
    --help | -h)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      printf '%s: unknown argument: %s (see --help)\n' "$TOOL_NAME" "$1" >&2
      exit 2
      ;;
  esac
done

command -v "$MAGICK_BIN" > /dev/null 2>&1 || {
  printf '%s: no %s on PATH (MAGICK_BIN overrides it)\n' "$TOOL_NAME" "$MAGICK_BIN" >&2
  exit 2
}

pass() { printf 'ok: %s\n' "$1"; }
fail() {
  printf '%s: FAIL: %s\n' "$TOOL_NAME" "$1" >&2
  FAILURES=$((FAILURES + 1))
}

assert_eq() { # got want what
  if [[ "$1" == "$2" ]]; then
    pass "$3"
  else
    fail "$3 (got '$1', want '$2')"
  fi
}

assert_contains() { # file pattern what
  if grep -q -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (no '$2' in $1)"
  fi
}

assert_absent() { # path what
  if [[ -e "$1" ]]; then
    fail "$2 ($1 exists)"
  else
    pass "$2"
  fi
}

# The value of `let skin.NAME = …` in a generated theme.plm.
theme_value() { # file name
  sed -n "s/^ *let skin\.$2 = \(.*\)$/\1/p" "$1" | head -n 1
}

# run_theme HOME ARGS… — run theme.sh with that HOME/XDG, stdout to $OUT_LOG,
# stderr to $ERR_LOG, exit status in $RC.
run_theme() {
  local home="$1"
  shift
  if HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    "$THEME_SH" "$@" > "$OUT_LOG" 2> "$ERR_LOG"; then
    RC=0
  else
    RC=$?
  fi
}

WORK="$(mktemp -d --tmpdir "${TOOL_NAME}.XXXXXX")"
OUT_LOG="$WORK/stdout.log"
ERR_LOG="$WORK/stderr.log"
printf '%s: workspace %s\n' "$TOOL_NAME" "$WORK"

# ---- fixtures ---------------------------------------------------------------

"$MAGICK_BIN" -size 320x240 gradient:'#08101e-#2f77b8' "$WORK/blue.png"
"$MAGICK_BIN" -size 320x240 gradient:'#f2efe8-#ffffff' "$WORK/light.png"
"$MAGICK_BIN" -size 320x240 xc:'#9a9a9a' "$WORK/gray.png"

# ---- 1. the legacy cache path, a coloured fixture ---------------------------

home1="$WORK/home1"
mkdir -p "$home1/.cache" "$home1/.config/pleamar"
printf 'sentinel\n' > "$home1/.config/pleamar/keep.txt"
printf '%s\n' "$WORK/blue.png" > "$home1/.cache/quickshell-wallpaper-path"

run_theme "$home1"
assert_eq "$RC" 0 "legacy cache path: exit 0"
theme1="$home1/.config/pleamar/theme.plm"
assert_contains "$theme1" '^library Skin strict {' "generated file is a strict Skin library"
assert_contains "$theme1" 'let skin\.on\.accent = #ffffff' "all eight skin names are declared"
# Golden values for this fixture: they pin the two samplers (a magick or
# algorithm change is expected to fail here and be re-blessed deliberately).
assert_eq "$(theme_value "$theme1" coal)" '#061c38' "blue fixture: coal = darkest Oklab cluster"
assert_eq "$(theme_value "$theme1" surface)" '#023663' "blue fixture: surface = second-darkest cluster"
assert_eq "$(theme_value "$theme1" ink)" '#66a6d7' "blue fixture: ink is light and readable"
assert_eq "$(theme_value "$theme1" accent)" '#0067cc' "blue fixture: accent = hue-matched mean (#006FCC family)"
assert_eq "$(theme_value "$theme1" 'ink\.dim')" "mix(skin.ink, skin.surface, 35%)" "ink.dim is the QS secondary step"
assert_contains "$home1/.config/pleamar/keep.txt" 'sentinel' "nothing else under ~/.config/pleamar is touched"

# ---- 2. the new cache path wins over the legacy one -------------------------

home2="$WORK/home2"
mkdir -p "$home2/.cache/pleamar"
printf '%s\n' "$WORK/light.png" > "$home2/.cache/pleamar/wallpaper-path"
printf '%s\n' "$WORK/blue.png" > "$home2/.cache/quickshell-wallpaper-path"
run_theme "$home2"
assert_eq "$RC" 0 "pleamar cache path: exit 0"
assert_contains "$OUT_LOG" "source $WORK/light.png" "INTERFACES §1.2 path wins over the legacy cache"
theme2="$home2/.config/pleamar/theme.plm"
# A light wallpaper: the clamp must give a dark ink that contrasts on surface.
ink2="$(theme_value "$theme2" ink)"
if [[ "$ink2" =~ ^#[0-9a-f]{6}$ ]]; then
  hex="${ink2#\#}"
  lum=$(((16#${hex:0:2} * 299 + 16#${hex:2:2} * 587 + 16#${hex:4:2} * 114) / 1000))
  if ((lum < 128)); then
    pass "light fixture: ink is a dark tone (readability clamp, luma $lum)"
  else
    fail "light fixture: ink is not dark ($ink2, luma $lum)"
  fi
else
  fail "light fixture: ink is not a colour ($ink2)"
fi

# ---- 3. --accent overrides the extracted accent only ------------------------

run_theme "$home1" --accent '#AbCdEf'
assert_eq "$RC" 0 "--accent: exit 0"
assert_eq "$(theme_value "$theme1" accent)" '#abcdef' "--accent: accent replaced (and lower-cased)"
assert_eq "$(theme_value "$theme1" coal)" '#061c38' "--accent: the sampled tones stay"

# ---- 4. --from-json, without a wallpaper ------------------------------------

home4="$WORK/home4"
mkdir -p "$home4"
printf '{"surface": "#101820", "ink": "#f0ead6", "accent": "#12ab34"}\n' > "$WORK/pal.json"
run_theme "$home4" --from-json "$WORK/pal.json"
assert_eq "$RC" 0 "--from-json without a wallpaper: exit 0"
theme4="$home4/.config/pleamar/theme.plm"
assert_eq "$(theme_value "$theme4" surface)" '#101820' "--from-json: surface taken"
assert_eq "$(theme_value "$theme4" ink)" '#f0ead6' "--from-json: ink taken"
assert_eq "$(theme_value "$theme4" accent)" '#12ab34' "--from-json: accent taken"
assert_eq "$(theme_value "$theme4" coal)" '#000000' "--from-json: unnamed tone falls back to QS colors.background"

# ---- 5. missing input: clear error, nothing written -------------------------

home5="$WORK/home5"
mkdir -p "$home5"
run_theme "$home5"
assert_eq "$RC" 1 "missing input: exit 1"
assert_absent "$home5/.config/pleamar/theme.plm" "missing input: no theme.plm written"
assert_contains "$ERR_LOG" 'nothing to extract' "missing input: the error says what is missing"

# ---- 6. a failed run leaves the last good file and no temp behind -----------

home6="$WORK/home6"
mkdir -p "$home6/.cache"
printf '%s\n' "$WORK/blue.png" > "$home6/.cache/quickshell-wallpaper-path"
run_theme "$home6"
before="$(sha256sum "$home6/.config/pleamar/theme.plm")"
run_theme "$home6" --accent 'not-a-colour'
assert_eq "$RC" 1 "bad --accent: exit 1"
after="$(sha256sum "$home6/.config/pleamar/theme.plm")"
assert_eq "$before" "$after" "bad --accent: theme.plm unchanged"
if compgen -G "$home6/.config/pleamar/.theme.plm.*" > /dev/null; then
  fail "bad --accent: temp file left behind"
else
  pass "bad --accent: no temp file left behind"
fi

# ---- 7. theme.default.plm is the seed, and it says what theme.sh emits -------

run_theme "$home4" --accent '#006fcc'
# The hex case is not part of the value: compare lower-cased.
default_lets="$(grep '^ *let skin\.' "$SCRIPT_DIR/theme.default.plm" | tr 'A-F' 'a-f')"
generated_lets="$(grep '^ *let skin\.' "$theme4" | tr 'A-F' 'a-f')"
assert_eq "$generated_lets" "$default_lets" "theme.default.plm matches theme.sh's no-wallpaper fallbacks"

# ---- 8. --help ---------------------------------------------------------------

run_theme "$WORK" --help
assert_eq "$RC" 0 "--help: exit 0"
assert_contains "$OUT_LOG" '--from-json' "--help: lists the options"

# ---- 9. the compiler: a /tmp consumer imports the generated theme.plm -------

PLEAMAR=""
if [[ "$PLEAMAR_BIN" == */* ]]; then
  [[ -x "$PLEAMAR_BIN" ]] && PLEAMAR="$PLEAMAR_BIN"
elif command -v "$PLEAMAR_BIN" > /dev/null 2>&1; then
  PLEAMAR="$(command -v "$PLEAMAR_BIN")"
fi

if [[ -z "$PLEAMAR" ]]; then
  printf 'note: %s not on PATH — consumer compile skipped (pass --pleamar FILE)\n' "$PLEAMAR_BIN"
else
  compile_consumer() { # dir theme.plm label
    local cons_dir="$1" theme_file="$2" label="$3"
    mkdir -p "$cons_dir"
    local rel_lib rel_theme
    rel_lib="$(realpath --relative-to="$cons_dir" "$PROJECT_DIR/lib")"
    rel_theme="$(realpath --relative-to="$cons_dir" "$theme_file")"
    cat > "$cons_dir/theme_proof.plm" << EOF
// /tmp consumer, generated by files/pleamar/scripts/theme/test.sh: a theme.plm
// together with lib/palette.plm, never in the repo.
import "$rel_lib/palette.plm"
import "$rel_lib/capsule.plm"
import "$rel_theme"

scene ThemeProof {
    surface { size: 320, 96; anchor: center }

    // D9: text size is a literal; the group is the one multiplier.
    group zoom {
        scale: ui
        Capsule(180, 40, fill: skin.surface, alpha: 1, scale: 1, rim: 0.05) {
            text "welcome" { size: 14; color: skin.ink }
            text "dim" { size: 12; color: skin.ink.dim }
        }
        box { from: 0, 0; size: 180, 3; corner: 1; color: skin.accent }
        box { from: 0, 3; size: 90, 3; corner: 1; color: skin.accent.hover }
        box { from: 90, 3; size: 90, 3; corner: 1; color: skin.accent.deep }
        text "x" { at: 4, 30; size: 12; color: skin.on.accent }
    }
}
EOF
    if env -u LD_LIBRARY_PATH "$PLEAMAR" --check "$cons_dir/theme_proof.plm" > "$OUT_LOG" 2> "$ERR_LOG"; then
      pass "$label: $(head -n 1 "$OUT_LOG")"
    else
      fail "$label ($(head -n 3 "$ERR_LOG"))"
    fi
  }
  compile_consumer "$WORK/consumer" "$theme1" "consumer with the generated theme.plm compiles"
  compile_consumer "$WORK/consumer-seed" "$SCRIPT_DIR/theme.default.plm" "consumer with theme.default.plm compiles"
fi

# ---- summary ----------------------------------------------------------------

printf '%s: %s\n' "$TOOL_NAME" "$( ((FAILURES == 0)) && echo 'all checks passed' || echo "$FAILURES check(s) failed")"
if ((KEEP == 1)); then
  printf '%s: kept %s\n' "$TOOL_NAME" "$WORK"
fi
((FAILURES == 0))
