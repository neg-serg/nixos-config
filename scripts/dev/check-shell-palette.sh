#!/usr/bin/env bash
# Guard: the zsh syntax theme and LS_COLORS agree, and both stay on-palette.
#
# Two files paint the same shell: files/shell/dircolors/dircolors is what `ls`
# and zsh completion use, files/shell/zsh-native-syntax/neg.ini is the
# zsh-native-syntax theme. The engine overlays the INI on LS_COLORS for
# extensions, and `ls` only ever sees LS_COLORS, so the same extension has to
# resolve to the same colour in both files — before this guard the two tables
# had drifted, and a file was one colour in the listing and another at the
# prompt. Where an extension appears twice (both files carry historical
# duplicates), the last entry wins, which is also what the engine's map and
# LS_COLORS matching do.
#
# Rules:
#   1. every extension present in both files maps to the same foreground hex;
#   2. every colour in both files is one of the palette stops below — the
#      palette is the point of the theme, an ad-hoc hex is how it drifts;
#   3. no 256-colour index survives (38;5;N / 48;5;N in dircolors, a bare
#      number as a colour in the INI): an index is whatever the terminal says
#      it is, which is exactly what the 24-bit rewrite removed.
#   4. the dircolors file still parses in the real implementations. Only
#      `*pattern`, `.ext` and keywords (TERM/COLOR/EIGHTBIT/OPTIONS, the type
#      names) are valid first tokens; a bare `bashrc` or `@.service` is not.
#      GNU's parser drops such a line silently, but uutils' — the `dircolors`
#      on PATH since coreutils moved to uutils — aborts the whole file with
#      "unrecognized keyword" and prints nothing, so `eval $(dircolors …)`
#      leaves LS_COLORS empty and every fresh shell (a new kitty window) falls
#      back to the built-in colours. This is the failure this guard missed when
#      it re-implemented the parser in awk.
#
# The palette is neg.nvim's (lua/neg/palette.lua) plus the two CIELAB-derived
# stops and the two 25% tints the theme needs. Extend the list together with
# the theme, so the guard records the decision.
#
# Usage: check-shell-palette.sh [repo-root]
#   DIRCOLORS_PARSERS  colon-separated parsers to run (default: `dircolors`
#                      from PATH). The flake check passes both GNU and uutils.
set -euo pipefail
export LC_ALL=C

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "$@")"
cd "$REPO_ROOT"

DIRCOLORS=files/shell/dircolors/dircolors
THEME=files/shell/zsh-native-syntax/neg.ini

PALETTE="
#363f4b #506a7d #6c7e96 #6e879f #7387a1 #a5c1e6 #d1e5ff
#395573 #005f87 #2b7694 #005faf #367cb0 #4779b3 #6289b3 #7095b0
#127978 #148787 #357b63 #127a57 #007a66
#1d4aaf #746b9e #a47ead #c8a8ef #6b0f2a #5f0000 #cf4f88
#15181f #0c1c30 #1c334e #223f73 #272727 #000000 #001f1a #1b040b
"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

# extension -> foreground hex, last occurrence wins
awk '
  /^\[/ { sec = $0; next }
  sec != "[file-extensions]" { next }
  /^[ \t]*;/ { next }
  {
    key = $0
    sub(/[ \t]*=.*/, "", key)
    if (key == "") next
    val = $0
    sub(/^[^=]*=/, "", val)
    sub(/;.*/, "", val)
    gsub(/[ \t]/, "", val)
    n = split(val, part, ",")
    fg = ""
    for (i = 1; i <= n; i++) {
      p = part[i]
      if (p == "" || p == "none") continue
      if (p == "bold" || p == "italic" || p == "underline") continue
      if (p == "standout" || p == "strikethrough") continue
      if (substr(p, 1, 3) == "bg:") continue
      fg = tolower(p)
      break
    }
    if (fg != "") ext[key] = fg
  }
  END { for (k in ext) print k, ext[k] }
' "$THEME" | sort > "$tmp/theme"

awk '
  /^\./ {
    name = substr($1, 2)
    n = split($2, a, ";")
    fg = ""
    for (i = 1; i <= n - 4; i++)
      if (a[i] == "38" && a[i + 1] == "2")
        fg = sprintf("#%02x%02x%02x", a[i + 2], a[i + 3], a[i + 4])
    if (fg != "") ext[name] = tolower(fg)
  }
  END { for (k in ext) print k, ext[k] }
' "$DIRCOLORS" | sort > "$tmp/dircolors"

# 1. same extension, same colour
join "$tmp/theme" "$tmp/dircolors" | awk '
  $2 != $3 { printf "  %-18s theme %s  dircolors %s\n", $1, $2, $3; bad = 1 }
  END { exit bad ? 1 : 0 }
' > "$tmp/mismatch" || true
if [ -s "$tmp/mismatch" ]; then
  cat "$tmp/mismatch" >&2
  echo "Shell palette: extension colours disagree between $THEME and $DIRCOLORS" >&2
  fail=1
fi

# 2. on-palette only
tr -s '[:space:]' '\n' <<< "$PALETTE" | sed '/^$/d' | sort -u > "$tmp/palette"
{
  awk '{ print $2 }' "$tmp/theme" "$tmp/dircolors"
  grep -vE '^[[:space:]]*[;#]' "$THEME" "$DIRCOLORS" 2> /dev/null \
    | grep -oE '#[0-9a-fA-F]{6}' | cut -d: -f2 || true
  grep -oE '(38|48);2;([0-9]{1,3};){2}[0-9]{1,3}' "$DIRCOLORS" 2> /dev/null \
    | awk -F';' '{ printf "#%02x%02x%02x\n", $3, $4, $5 }' || true
} | tr 'A-F' 'a-f' | sort -u > "$tmp/used"
comm -23 "$tmp/used" "$tmp/palette" > "$tmp/off" || true
if [ -s "$tmp/off" ]; then
  echo "Shell palette: colours outside the palette:" >&2
  sed 's/^/  /' "$tmp/off" >&2
  fail=1
fi

# 3. no 256-colour indexes left
if grep -qE '(38|48);5;[0-9]+' "$DIRCOLORS"; then
  echo "Shell palette: 256-colour indexes left in $DIRCOLORS:" >&2
  grep -nE '(38|48);5;[0-9]+' "$DIRCOLORS" | head -8 | sed 's/^/  /' >&2
  echo "  … $(grep -cE '(38|48);5;[0-9]+' "$DIRCOLORS") lines in total" >&2
  fail=1
fi
if awk '
  /^\[/ { sec = $0; next }
  sec != "[file-extensions]" { next }
  /^[ \t]*;/ { next }
  {
    val = $0
    sub(/^[^=]*=/, "", val)
    sub(/;.*/, "", val)
    gsub(/[ \t]/, "", val)
    n = split(val, part, ",")
    for (i = 1; i <= n; i++)
      if (part[i] ~ /^[0-9]+$/ || part[i] ~ /^bg:[0-9]+$/) {
        printf "  %d: %s\n", FNR, $0
        found = 1
      }
  }
  END { exit found ? 1 : 0 }
' "$THEME" > "$tmp/indexes" 2>&1; then
  :
else
  head -8 "$tmp/indexes" >&2
  echo "Shell palette: colour indexes left in $THEME" >&2
  fail=1
fi

# 4. the file still parses in the real dircolors implementations
#    (DIRCOLORS_PARSERS, colon-separated; default: `dircolors` from PATH). A
#    parser that is absent is a skip locally and a failure when the caller says
#    the parser is required (the flake check passes both and requires them), so
#    the gate cannot quietly degrade to nothing.
IFS=: read -r -a parsers <<< "${DIRCOLORS_PARSERS:-dircolors}"
for parser in "${parsers[@]}"; do
  bin="$(command -v "$parser" 2> /dev/null || true)"
  if [ -z "$bin" ]; then
    if [ "${DIRCOLORS_PARSERS_REQUIRED:-0}" = 1 ]; then
      echo "Shell palette: required dircolors parser missing: $parser" >&2
      fail=1
    else
      echo "Shell palette: dircolors parser not found, skipping: $parser"
    fi
    continue
  fi
  if ! TERM=xterm-kitty "$bin" "$DIRCOLORS" > "$tmp/parsed" 2> "$tmp/parsed.err"; then
    echo "Shell palette: $bin rejects $DIRCOLORS:" >&2
    sed 's/^/  /' "$tmp/parsed.err" >&2
    # uutils names the offending token but not the line, so point at the lines
    # whose first token is neither a pattern (./*) nor a keyword (ALL_CAPS).
    awk '
      /^[[:space:]]*(#|$)/ { next }
      $1 ~ /^[*.]/ || $1 ~ /^[A-Z][A-Z_]*$/ { next }
      n < 10 { printf "  %d: %s\n", FNR, $0; n++ }
    ' "$DIRCOLORS" >&2
    fail=1
    continue
  fi
  value="$(sed -n "s/^LS_COLORS='\(.*\)';$/\1/p" "$tmp/parsed")"
  if [ "${#value}" -lt 100 ]; then
    echo "Shell palette: $bin parsed $DIRCOLORS into an empty LS_COLORS" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Shell palette guard: FAILED" >&2
  exit 1
fi
