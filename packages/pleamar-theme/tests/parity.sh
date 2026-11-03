#!/usr/bin/env bash
# Parity harness: run the shell pipeline and the Rust port side by side on the
# same fixtures and compare everything a consumer depends on.
#
#   tests/parity.sh [--bin PATH] [--shell PATH]
#
# Env: THEME_BIN / THEME_SH override the paths. The shell reference is
# files/pleamar/scripts/theme/theme.sh by default; after the integration
# deletes it, pass --shell (or THEME_SH) to a saved copy.
#
# Every scenario builds the same HOME/XDG tree twice — once for each side — so
# the generated paths are identical, and compares:
#   * exit status, stdout and stderr byte for byte;
#   * theme.plm byte for byte, except the `// written:` timestamp line (the
#     one field that changes between two runs; a same-second pair also matches
#     exactly and the harness says so);
#   * the file mode, the files under the tree, and the caches (everything but
#     the generated theme.plm), plus the absence of temp files;
#   * the unchanged-file shortcut on a second run.
#
# Exit: 0 when every check passed, 1 on a mismatch, 2 for a missing tool/usage.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
BIN=${THEME_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/pleamar-theme}
SHELL=${THEME_SH:-$(cd -- "$ROOT/../.." && pwd)/files/pleamar/scripts/theme/theme.sh}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      [ $# -ge 2 ] || {
        echo "parity: --bin needs a FILE" >&2
        exit 2
      }
      BIN=$2
      shift 2
      ;;
    --shell)
      [ $# -ge 2 ] || {
        echo "parity: --shell needs a FILE" >&2
        exit 2
      }
      SHELL=$2
      shift 2
      ;;
    --help | -h)
      sed -n '2,21p' "$0"
      exit 0
      ;;
    *)
      echo "parity: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

[ -x "$BIN" ] || {
  echo "parity: binary not executable: $BIN" >&2
  exit 2
}
[ -r "$SHELL" ] || {
  echo "parity: shell pipeline not readable: $SHELL" >&2
  exit 2
}
command -v magick > /dev/null 2>&1 || {
  echo "parity: no magick on PATH" >&2
  exit 2
}
command -v jq > /dev/null 2>&1 || {
  echo "parity: no jq on PATH" >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-theme-parity.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

FAILED=0
PASSED=0
pass() {
  PASSED=$((PASSED + 1))
  printf 'PASS  %s\n' "$1"
}
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s\n' "$1" >&2
}
section() { printf '\n== %s ==\n' "$1"; }

HOME_DIR=$WORK/home
EXTRA_ENV=()

magick -size 320x240 gradient:'#08101e-#2f77b8' "$WORK/blue.png"
magick -size 320x240 gradient:'#f2efe8-#ffffff' "$WORK/light.png"
printf 'hello\n' > "$WORK/not-an-image.txt"
printf '{"surface": "#101820", "ink": "#f0ead6", "accent": "#12ab34"}\n' > "$WORK/pal.json"
printf 'not json\n' > "$WORK/bad.json"
printf '{}\n' > "$WORK/empty.json"
printf '{"coal": "#AbC", "accent": 42}\n' > "$WORK/short.json"

# ---- setups (each recreates HOME from scratch) -----------------------------

base_home() {
  rm -rf -- "$HOME_DIR"
  mkdir -p "$HOME_DIR/.cache" "$HOME_DIR/.config/pleamar"
  printf 'sentinel\n' > "$HOME_DIR/.config/pleamar/keep.txt"
}

# The legacy `$XDG_CACHE_HOME/quickshell-wallpaper-path` was dropped from the port on
# 2026-11-03 (nothing writes it since the shell that introduced it was deleted), so
# there is no scenario for it any more: the canonical producer path is the only one,
# and a saved shell copy would disagree with the port exactly there.
setup_canonical_blue() {
  base_home
  mkdir -p "$HOME_DIR/.cache/pleamar"
  printf '%s\n' "$WORK/blue.png" > "$HOME_DIR/.cache/pleamar/wallpaper-path"
}

setup_canonical_light() {
  base_home
  mkdir -p "$HOME_DIR/.cache/pleamar"
  printf '%s\n' "$WORK/light.png" > "$HOME_DIR/.cache/pleamar/wallpaper-path"
}

setup_mode_file() {
  setup_canonical_blue
  printf ' l i g h t \n\n' > "$HOME_DIR/.config/pleamar/theme.mode"
}

setup_empty() {
  rm -rf -- "$HOME_DIR"
  mkdir -p "$HOME_DIR"
}

setup_cache_gone() {
  base_home
  mkdir -p "$HOME_DIR/.cache/pleamar"
  printf '%s\n' "$WORK/gone.png" > "$HOME_DIR/.cache/pleamar/wallpaper-path"
}

setup_not_image() {
  base_home
  mkdir -p "$HOME_DIR/.cache/pleamar"
  printf '%s\n' "$WORK/not-an-image.txt" > "$HOME_DIR/.cache/pleamar/wallpaper-path"
}

# ---- runners and comparison ------------------------------------------------

snapshot() { # side
  local side=$1
  if [ -f "$HOME_DIR/.config/pleamar/theme.plm" ]; then
    cp "$HOME_DIR/.config/pleamar/theme.plm" "$WORK/$side.theme"
    stat -c '%a' "$HOME_DIR/.config/pleamar/theme.plm" > "$WORK/$side.mode"
  else
    : > "$WORK/$side.theme"
    echo absent > "$WORK/$side.mode"
  fi
  (cd "$HOME_DIR" && find . \( -type f -o -type l \) ! -path './.config/pleamar/theme.plm' \
    -exec sha256sum {} + 2> /dev/null | sort) > "$WORK/$side.tree"
  if find "$HOME_DIR/.config/pleamar" -maxdepth 1 -name '.theme.plm.*' 2> /dev/null | grep -q .; then
    echo leftovers > "$WORK/$side.temp"
  else
    echo clean > "$WORK/$side.temp"
  fi
}

invoke() { # side tool args...
  local side=$1 tool=$2
  shift 2
  if env "${EXTRA_ENV[@]}" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_CACHE_HOME="$HOME_DIR/.cache" "$tool" "$@" > "$WORK/$side.out" 2> "$WORK/$side.err"; then
    echo 0 > "$WORK/$side.rc"
  else
    echo $? > "$WORK/$side.rc"
  fi
  snapshot "$side"
}

tool_for() { # side
  if [ "$1" = rust ]; then printf '%s' "$BIN"; else printf '%s' "$SHELL"; fi
}

run_side() { # side setup-fn args...
  local side=$1 setup=$2
  shift 2
  "$setup"
  invoke "$side" "$(tool_for "$side")" "$@"
}

compare_side() { # label
  local label=$1 ok=1
  if ! cmp -s "$WORK/shell.rc" "$WORK/rust.rc"; then
    fail "$label: exit status (shell $(cat "$WORK/shell.rc"), rust $(cat "$WORK/rust.rc"))"
    ok=0
  fi
  if ! cmp -s "$WORK/shell.out" "$WORK/rust.out"; then
    fail "$label: stdout"
    diff -u "$WORK/shell.out" "$WORK/rust.out" | head -n 20 >&2 || true
    ok=0
  fi
  if ! cmp -s "$WORK/shell.err" "$WORK/rust.err"; then
    fail "$label: stderr"
    diff -u "$WORK/shell.err" "$WORK/rust.err" | head -n 20 >&2 || true
    ok=0
  fi
  grep -v '^// written:' "$WORK/shell.theme" > "$WORK/shell.norm" || true
  grep -v '^// written:' "$WORK/rust.theme" > "$WORK/rust.norm" || true
  if ! cmp -s "$WORK/shell.norm" "$WORK/rust.norm"; then
    fail "$label: theme.plm (without // written:)"
    diff -u "$WORK/shell.norm" "$WORK/rust.norm" | head -n 30 >&2 || true
    ok=0
  fi
  if ! cmp -s "$WORK/shell.mode" "$WORK/rust.mode"; then
    fail "$label: theme.plm mode (shell $(cat "$WORK/shell.mode"), rust $(cat "$WORK/rust.mode"))"
    ok=0
  fi
  if ! cmp -s "$WORK/shell.tree" "$WORK/rust.tree"; then
    fail "$label: files/caches under HOME differ"
    diff -u "$WORK/shell.tree" "$WORK/rust.tree" | head -n 20 >&2 || true
    ok=0
  fi
  if ! cmp -s "$WORK/shell.temp" "$WORK/rust.temp"; then
    fail "$label: temp-file leftovers differ"
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then pass "$label"; fi
}

scenario() { # label setup-fn args...
  local label=$1 setup=$2
  shift 2
  EXTRA_ENV=()
  run_side shell "$setup" "$@"
  run_side rust "$setup" "$@"
  compare_side "$label"
}

# ---- scenarios -------------------------------------------------------------

section "wallpaper resolution and golden output"
scenario "canonical cache path, blue fixture" setup_canonical_blue

section "modes and the switch file"
scenario "--mode dark on a light wallpaper" setup_canonical_light --mode dark
scenario "theme.mode=light on a dark wallpaper" setup_mode_file

section "explicit colours"
scenario "--accent wins and is lower-cased" setup_canonical_blue --accent '#AbCdEf'
scenario "--from-json without a wallpaper" setup_empty --from-json "$WORK/pal.json"
scenario "--accent wins over --from-json" setup_empty --accent '#ABCDEF' --from-json "$WORK/pal.json"
scenario "short forms and numeric JSON values" setup_empty --from-json "$WORK/short.json"

section "errors"
scenario "nothing to extract" setup_empty
scenario "bad --accent" setup_canonical_blue --accent not-a-colour
scenario "unreadable --wallpaper" setup_empty --wallpaper "$WORK/gone.png"
scenario "unknown argument" setup_canonical_blue --nope
scenario "missing option value" setup_canonical_blue --wallpaper
scenario "bad --mode" setup_canonical_blue --mode blue
scenario "bad JSON" setup_empty --from-json "$WORK/bad.json"
scenario "empty JSON object" setup_empty --from-json "$WORK/empty.json"
scenario "--help" setup_canonical_blue --help

section "external tools"
EXTRA_ENV=(MAGICK_BIN=/nonexistent/magick)
run_side shell setup_canonical_blue
run_side rust setup_canonical_blue
compare_side "missing magick warns and falls back"
EXTRA_ENV=(JQ_BIN=/nonexistent/jq)
run_side shell setup_empty --from-json "$WORK/pal.json"
run_side rust setup_empty --from-json "$WORK/pal.json"
compare_side "missing jq (--from-json)"
EXTRA_ENV=()

section "a sample that is not an image"
scenario "warns, then uses --accent" setup_not_image --accent '#112233'
scenario "cache path whose file is gone" setup_cache_gone --accent '#112233'
scenario "a directory as --wallpaper" setup_empty --wallpaper "$WORK"

section "the unchanged shortcut"
for side in shell rust; do
  setup_canonical_blue
  tool=$(tool_for "$side")
  invoke "$side" "$tool"
  first=$(sha256sum "$HOME_DIR/.config/pleamar/theme.plm" | cut -d' ' -f1)
  invoke "$side" "$tool"
  second=$(sha256sum "$HOME_DIR/.config/pleamar/theme.plm" | cut -d' ' -f1)
  if [ "$first" = "$second" ]; then
    pass "$side: the second run left theme.plm untouched"
  else
    fail "$side: the second run rewrote theme.plm"
  fi
done
compare_side "a second run for the same wallpaper is unchanged"

section "the timestamp is the only field a rerun changes"
run_side shell setup_canonical_blue
run_side rust setup_canonical_blue
if cmp -s "$WORK/shell.theme" "$WORK/rust.theme"; then
  printf 'note: this run landed in the same second, so // written: matched too\n'
else
  printf 'note: // written: differs by the clock (the comparison above ignores it)\n'
fi

section "the unchanged comparison also ignores the source path"
setup_source_change() {
  base_home
  magick -size 32x32 xc:'#08101e' "$WORK/one.png"
  cp "$WORK/one.png" "$WORK/two.png"
  mkdir -p "$HOME_DIR/.cache/pleamar"
  printf '%s\n' "$WORK/one.png" > "$HOME_DIR/.cache/pleamar/wallpaper-path"
}
source_change_run() { # side tool
  local side=$1 tool=$2 first second
  setup_source_change
  HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" XDG_CACHE_HOME="$HOME_DIR/.cache" \
    "$tool" > /dev/null 2>&1
  first=$(sha256sum "$HOME_DIR/.config/pleamar/theme.plm" | cut -d' ' -f1)
  printf '%s\n' "$WORK/two.png" > "$HOME_DIR/.cache/pleamar/wallpaper-path"
  if HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" XDG_CACHE_HOME="$HOME_DIR/.cache" \
    "$tool" > "$WORK/$side.out" 2> "$WORK/$side.err"; then
    echo 0 > "$WORK/$side.rc"
  else
    echo $? > "$WORK/$side.rc"
  fi
  second=$(sha256sum "$HOME_DIR/.config/pleamar/theme.plm" | cut -d' ' -f1)
  if [ "$first" = "$second" ]; then echo same > "$WORK/$side.same"; else echo diff > "$WORK/$side.same"; fi
  snapshot "$side"
}
source_change_run shell "$SHELL"
source_change_run rust "$BIN"
compare_side "a new source with the same colours leaves the file alone"
if [ "$(cat "$WORK/shell.same")" = same ] && [ "$(cat "$WORK/rust.same")" = same ]; then
  pass "both sides left theme.plm untouched (source line included)"
else
  fail "a source-only change rewrote theme.plm"
fi

section "HOME/XDG spelling is preserved in paths and notes"
slash_run() { # side tool
  local side=$1 tool=$2
  rm -rf "$HOME_DIR" "$WORK/cfg" "$WORK/cache"
  mkdir -p "$HOME_DIR" "$WORK/cfg/pleamar" "$WORK/cache/pleamar"
  printf 'light\n' > "$WORK/cfg/pleamar/theme.mode"
  printf '%s\n' "$WORK/blue.png" > "$WORK/cache/pleamar/wallpaper-path"
  if HOME="$HOME_DIR" XDG_CONFIG_HOME="$WORK/cfg/" XDG_CACHE_HOME="$WORK/cache/" \
    "$tool" > "$WORK/$side.out" 2> "$WORK/$side.err"; then
    echo 0 > "$WORK/$side.rc"
  else
    echo $? > "$WORK/$side.rc"
  fi
  cp "$WORK/cfg/pleamar/theme.plm" "$WORK/$side.theme"
  stat -c '%a' "$WORK/cfg/pleamar/theme.plm" > "$WORK/$side.mode"
  : > "$WORK/$side.tree"
  echo clean > "$WORK/$side.temp"
}
slash_run shell "$SHELL"
slash_run rust "$BIN"
compare_side "a trailing slash stays doubled, as the shell printed it"

section "HOME is required before anything else"
for side in shell rust; do
  tool=$(tool_for "$side")
  if env -u HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME "$tool" --help \
    > "$WORK/$side.out" 2> "$WORK/$side.err"; then
    echo 0 > "$WORK/$side.rc"
  else
    echo $? > "$WORK/$side.rc"
  fi
  : > "$WORK/$side.theme"
  echo absent > "$WORK/$side.mode"
  : > "$WORK/$side.tree"
  echo clean > "$WORK/$side.temp"
done
compare_side "no HOME: exit 1 and the same message, even for --help"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASSED" "$FAILED"
((FAILED == 0))
