#!/usr/bin/env bash
# Check the live bar's geometry against the invariants its design rests on.
#
# `pleamar --say bar describe` is the engine's own account of where every zone
# is, so this gate needs no screenshots and no arithmetic of its own: it reads
# the rectangles and holds them to the rules the scenes are written by —
#
#   * the strip band is the surface's last 25 px (y 10, h 25);
#   * the left row starts at the 4 px side margin, the right row ends 4 px
#     from the screen's edge — the two insets are symmetric;
#   * every inter-widget gap in a row is the same 7 px;
#   * zones never overlap, and none leaves the panel.
#
# Widths themselves are deliberately NOT checked: they are content-sized now
# (`vol.w`, `mic.w`, `ws.w`, `weather.w`, the sysmon pair count), so they change
# with the audio route, the reading and the workspace. The invariants are what
# must survive those changes; a hard-coded width table would be stale within a
# day, which is how `tests/bar.describe.txt` went wrong.
#
# The session is a precondition, like the pleamar binary in check-plm.sh: with
# no bar running there is nothing to measure, so that is a skip with a notice
# and exit 0. `--describe FILE` reads a saved describe instead, which is what
# the script's own failure case is tested with.
#
# Exit status: 1 when an invariant is broken, 0 otherwise.
set -euo pipefail

SCENE="bar"
DESCRIBE_FILE=""
while (($#)); do
  case "$1" in
    --scene)
      SCENE="${2:?--scene needs a name}"
      shift 2
      ;;
    --describe)
      DESCRIBE_FILE="${2:?--describe needs a path}"
      shift 2
      ;;
    -h | --help)
      sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$DESCRIBE_FILE" ]]; then
  OUT="$(cat "$DESCRIBE_FILE")"
else
  command -v pleamar > /dev/null 2>&1 || {
    echo "pleamar not found — skipping the bar geometry check (build/install pkgs.pleamar to enable it)"
    exit 0
  }
  if ! OUT="$(pleamar --say "$SCENE" describe 2>&1)"; then
    echo "the '$SCENE' scene is not running — skipping the geometry check (start it, then run this again)"
    exit 0
  fi
fi

printf '%s\n' "$OUT" | awk -v scene="$SCENE" '
  # -- geometry of one describe run ---------------------------------------
  BEGIN { n = 0; panelw = 0; panelh = 0; failed = 0; inmain = 0 }
  function fail(msg) { printf "  ✗ %s\n", msg; failed = 1 }
  function ok(msg)   { printf "  · %s\n", msg }

  /^[a-z_]+ \(screen [0-9]+\) · panel / {
    # A surface header. Only the unnamed `main` one is the strip; the named
    # surfaces (bartip, barmenu) are cards and have their own geometry.
    inmain = ($1 == "main")
    if (inmain) {
      match($0, /panel [0-9]+×[0-9]+/)
      split(substr($0, RSTART + 6, RLENGTH - 6), d, "×")
      panelw = d[1] + 0; panelh = d[2] + 0
    }
    next
  }
  !inmain { next }
  / at [0-9-]+,[0-9-]+ [0-9]+×[0-9]+ *$/ {
    # A zone line: `<type> <name> «label» [· selected] at X,Y W×H`.
    match($0, / at [0-9-]+,[0-9-]+ [0-9]+×[0-9]+ *$/)
    geom = substr($0, RSTART + 4, RLENGTH - 4)
    split(geom, a, /[,× ]+/)
    name = $2; sub(/#.*/, "", name)
    n++
    zx[n] = a[1] + 0; zy[n] = a[2] + 0; zw[n] = a[3] + 0; zh[n] = a[4] + 0; zn[n] = name
  }
  END {
    if (panelw == 0) { print "no main panel in the describe output"; exit 2 }
    if (n == 0)      { print "the describe output listed no zones"; exit 2 }
    printf "%s: %d zone(s) on a %dx%d panel\n", scene, n, panelw, panelh

    # -- which zones are widgets of the strip -----------------------------
    # `strip_hover` covers the whole strip (it is the pointer target, not a
    # widget) and `tray_reveal` is a 4 px hotzone abutting the last widget.
    m = 0
    for (i = 1; i <= n; i++) {
      if (zn[i] == "strip_hover" || zn[i] == "tray_reveal") continue
      m++; wx[m] = zx[i]; wy[m] = zy[i]; ww[m] = zw[i]; wh[m] = zh[i]; wn[m] = zn[i]
    }
    if (m < 2) { print "  ✗ found fewer than two widgets to check"; exit 1 }

    # -- bounds and the band -----------------------------------------------
    for (i = 1; i <= m; i++) {
      if (wx[i] < 0 || wx[i] + ww[i] > panelw)
        fail(wn[i] " leaves the panel horizontally (" wx[i] ".." wx[i] + ww[i] " of " panelw ")")
      if (wy[i] < 0 || wy[i] + wh[i] > panelh)
        fail(wn[i] " leaves the panel vertically (" wy[i] ".." wy[i] + wh[i] " of " panelh ")")
      if (wy[i] != 10 || wh[i] != 25)
        fail(wn[i] " is not on the strip band (y " wy[i] ", h " wh[i] "; expected y 10, h 25)")
    }

    # -- sort by x (insertion; a strip has a dozen zones) ------------------
    for (i = 2; i <= m; i++) {
      for (j = i; j > 1 && wx[j - 1] > wx[j]; j--) {
        t = wx[j]; wx[j] = wx[j - 1]; wx[j - 1] = t
        t = wy[j]; wy[j] = wy[j - 1]; wy[j - 1] = t
        t = ww[j]; ww[j] = ww[j - 1]; ww[j - 1] = t
        t = wh[j]; wh[j] = wh[j - 1]; wh[j - 1] = t
        t = wn[j]; wn[j] = wn[j - 1]; wn[j - 1] = t
      }
    }

    # -- no overlaps -------------------------------------------------------
    for (i = 2; i <= m; i++) {
      prev_end = wx[i - 1] + ww[i - 1]
      if (wx[i] < prev_end)
        fail(wn[i - 1] " and " wn[i] " overlap (" prev_end " > " wx[i] ")")
    }

    # -- the two side insets and the gap between neighbours ----------------
    # The row a widget belongs to is decided by the side of the panel it
    # sits on, so a left-row widget added or removed needs no edit here.
    left_n = 0; right_n = 0
    for (i = 1; i <= m; i++) {
      if (wx[i] + ww[i] / 2 < panelw / 2) { left_n++; lx[left_n] = wx[i]; lw[left_n] = ww[i]; ln[left_n] = wn[i] }
      else                                { right_n++; rx[right_n] = wx[i]; rw[right_n] = ww[i]; rn[right_n] = wn[i] }
    }
    if (left_n == 0 || right_n == 0) fail("one of the two rows is empty; the bar draws both")

    if (left_n > 0 && lx[1] != 4)
      fail("the left row starts at x " lx[1] ", not the 4 px side margin")
    if (right_n > 0) {
      last_end = rx[right_n] + rw[right_n]
      if (last_end != panelw - 4)
        fail("the right row ends at " last_end ", not " panelw - 4 " (" panelw " − 4)")
    }
    for (i = 2; i <= left_n; i++) {
      gap = lx[i] - (lx[i - 1] + lw[i - 1])
      if (gap != 7) fail("gap " ln[i - 1] " → " ln[i] " is " gap " px, not 7")
    }
    for (i = 2; i <= right_n; i++) {
      gap = rx[i] - (rx[i - 1] + rw[i - 1])
      if (gap != 7) fail("gap " rn[i - 1] " → " rn[i] " is " gap " px, not 7")
    }

    if (!failed) ok("bounds, band, insets and gaps hold")
    exit failed ? 1 : 0
  }
'
