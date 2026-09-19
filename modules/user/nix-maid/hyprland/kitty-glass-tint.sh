#!/usr/bin/env bash
# Push a background colour into the running rmpc scratchpad pane.
#
# kitty takes its background at launch, so following the record means writing
# into the live window. Each scratchpad pane is its own kitty instance (hyprscratch
# starts it from a systemd user service, so it never joins the session's kitty),
# which is why the socket is taken from the pane's own KITTY_LISTEN_ON: the call
# can only reach windows on that instance.
#
# Deliberately no --all: with --all kitty 0.48 ignores the match and repaints
# every window on the instance, which would hit the terminals in use if rmpc is
# ever run inside the session's kitty. Matching the pane's own process keeps the
# target to that window.
#
# $1: a #rrggbb colour, or #000000 for kitty's own background.
set -euo pipefail
color="${1:-}"
[ -n "$color" ] || exit 0
kitten_bin="@kitten@"

for pid in $(pgrep -x rmpc 2> /dev/null || true); do
  addr="$(tr '\0' '\n' < "/proc/$pid/environ" 2> /dev/null | sed -n 's/^KITTY_LISTEN_ON=//p')"
  [ -n "$addr" ] || continue
  "$kitten_bin" @ --to "$addr" set-colors --match cmdline:rmpc "background=$color" > /dev/null 2>&1 || true
done
exit 0
