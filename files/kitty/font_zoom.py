#!/usr/bin/env python
# License: GPLv3 Copyright: 2026, neg
"""Scale the OS window font size with the OS window size (kitty watcher).

kitty has no built-in "shrink the font when the window shrinks": the cell size
is fixed by font_size and a smaller window simply shows fewer cells. This
watcher adds that behaviour:

* the size + font size a window settles at on startup is the **anchor**, so a
  new terminal always starts at the configured ``font_size`` (the window
  manager tiling the window right after launch must not count as a resize);
* every later resize sets ``font_size = anchor_font * sqrt(area / anchor_area)``
  -- the geometric mean of both axes, so stretching a window in one direction
  does not give an absurdly large/small font;
* the result is clamped to [MIN_FONT_SIZE, MAX_FONT_FACTOR * anchor_font] and
  rounded to quarter points, changes below DEADZONE points are dropped, and
  SELF_CHANGE_GRACE ignores events caused by our own change -- together these
  terminate the ``font change -> cell count change -> on_resize`` loop;
* a font size change at an unchanged window size was not caused by resizing:
  it comes from outside the watcher (zoom hotkey ``change_font_size current
  +0.5``, reset ``change_font_size current 0``, wheel, or ``all`` from another
  OS window). Such a size is adopted as the new anchor instead of being scaled
  back, so manual zoom survives later resizes (SIZE_SLOP tolerates the pixel
  jitter a window manager may add while re-laying-out);
* the watcher can be switched off per OS window with the user variable
  ``font_zoom`` (``kitten @ set-user-vars font_zoom=off``, the ``off``/``on``/
  ``toggle`` modes of the ``kitty-font-zoom`` script, or ``OSC 1337;
  SetUserVar`` from the shell -- see docs/howto/kitty-font-zoom.md). Paused
  means: font goes back to the plain configured size and stops following the
  window, i.e. exactly the pre-watcher kitty behaviour.

Enable with ``watcher font_zoom.py`` in kitty.conf (path relative to the kitty
config dir). Limitations: the font size is per OS window, so resizing a single
split also rescales the whole OS window.
"""

from __future__ import annotations

import math
import time
from typing import TYPE_CHECKING, Any, TypedDict

if TYPE_CHECKING:
    from kitty.boss import Boss
    from kitty.window import Window

# User variable that pauses the watcher for one OS window (off/on/toggle).
PAUSE_VAR = "font_zoom"
MIN_FONT_SIZE = 6.0
MAX_FONT_FACTOR = 2.0
DEADZONE = 0.25
SELF_CHANGE_GRACE = 0.15
# The window manager tiles/resizes a fresh window right after launch; resize
# events during this grace period only move the anchor and never touch the font.
STARTUP_SETTLE = 1.5
# Relative tolerance for "the window size did not change" -- a font change makes
# kitty update its size hints, and some window managers answer with a few pixels
# of jitter (Hyprland: 1152x1055 -> 1162x1065 when a window goes floating).
SIZE_SLOP = 0.02


class Anchor(TypedDict):
    width: int
    height: int
    font_size: float


_anchors: dict[int, Anchor] = {}
_first_seen: dict[int, float] = {}
_last_pixels: dict[int, tuple[int, int]] = {}
_last_self_change: dict[int, float] = {}
_paused: set[int] = (
    set()
)  # OS windows whose font was un-followed (font_zoom=off)


def _os_window_pixels(os_window_id: int) -> tuple[int, int] | None:
    from kitty.fast_data_types import get_os_window_size

    size = get_os_window_size(os_window_id)
    if not size:
        return None
    return max(1, size["width"]), max(1, size["height"])


def _current_font_size(os_window_id: int) -> float:
    from kitty.fast_data_types import get_options, os_window_font_size

    return os_window_font_size(os_window_id) or get_options().font_size


def _apply(boss: Boss, os_window_id: int, font_size: float) -> None:
    # _change_font_size() is the only way to target an OS window that is not
    # the active one; the public change_font_size() falls back to the active
    # window. See kitty/rc/set_font_size.py -- it has no --match either.
    changer = getattr(boss, "_change_font_size", None)
    if changer is not None:
        changer({os_window_id: font_size})
    else:
        boss.change_font_size(False, None, font_size)


def _same_size(a: tuple[int, int], b: tuple[int, int]) -> bool:
    return (
        abs(a[0] - b[0]) <= SIZE_SLOP * b[0]
        and abs(a[1] - b[1]) <= SIZE_SLOP * b[1]
    )


def _forget(os_window_id: int) -> None:
    _anchors.pop(os_window_id, None)
    _first_seen.pop(os_window_id, None)
    _last_pixels.pop(os_window_id, None)


def _reanchor(window: Window) -> None:
    """Start following the window size again from where it is now."""
    pixels = _os_window_pixels(window.os_window_id)
    if pixels is None:
        return
    _anchors[window.os_window_id] = Anchor(
        width=pixels[0],
        height=pixels[1],
        font_size=_current_font_size(window.os_window_id),
    )
    # Past the initial grace, so scaling applies on the very next resize.
    _first_seen[window.os_window_id] = time.monotonic() - STARTUP_SETTLE - 1


def _target(anchor: Anchor, width: int, height: int) -> float:
    area_ratio = (width * height) / (anchor["width"] * anchor["height"])
    target = anchor["font_size"] * math.sqrt(area_ratio)
    target = max(
        MIN_FONT_SIZE, min(target, anchor["font_size"] * MAX_FONT_FACTOR)
    )
    return round(target * 4) / 4


def on_resize(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    try:
        _scale(boss, window, data)
    except Exception:
        import traceback

        traceback.print_exc()


def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    try:
        if data.get("key") != PAUSE_VAR:
            return
        value = data.get("value") or ""
        if isinstance(value, bytes | bytearray):
            value = value.decode("utf-8", "replace")
        os_window_id = window.os_window_id
        if value.strip().lower() in ("off", "0", "no", "false", "pause"):
            # Back to the pre-watcher behaviour: the plain configured size and no
            # following. Same size `change_font_size current 0` would restore.
            from kitty.fast_data_types import get_options

            _paused.add(os_window_id)
            _forget(os_window_id)
            _apply(boss, os_window_id, get_options().font_size)
        else:
            _paused.discard(os_window_id)
            _reanchor(window)
    except Exception:
        import traceback

        traceback.print_exc()


def _scale(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    os_window_id = window.os_window_id
    now = time.monotonic()
    if now - _last_self_change.get(os_window_id, 0.0) < SELF_CHANGE_GRACE:
        return
    for stale_id in (set(_anchors) | set(_last_pixels) | _paused) - set(
        boss.os_window_map
    ):
        _forget(stale_id)
        _paused.discard(stale_id)
    pixels = _os_window_pixels(os_window_id)
    if pixels is None:
        return
    width, height = pixels
    previous_pixels = _last_pixels.get(os_window_id)
    # Tracked even while paused: a resize during the pause must not look like
    # "same size, different font" (a manual change) on the next event.
    _last_pixels[os_window_id] = (width, height)
    if os_window_id in _paused:
        return
    font_size = _current_font_size(os_window_id)
    anchor = _anchors.get(os_window_id)
    if anchor is None:
        _first_seen[os_window_id] = now
        _anchors[os_window_id] = Anchor(
            width=width, height=height, font_size=font_size
        )
        return
    if now - _first_seen[os_window_id] < STARTUP_SETTLE:
        _anchors[os_window_id] = Anchor(
            width=width, height=height, font_size=font_size
        )
        return
    target = _target(anchor, width, height)
    if (
        previous_pixels is not None
        and _same_size(previous_pixels, (width, height))
        and abs(font_size - target) >= DEADZONE
    ):
        # Same window size, different font: someone outside the watcher changed
        # it (zoom hotkey, wheel, reset). Adopt it as the new baseline, else the
        # next event would scale it back to the anchor's size.
        _anchors[os_window_id] = Anchor(
            width=width, height=height, font_size=font_size
        )
        return
    if abs(target - font_size) < DEADZONE:
        return
    _last_self_change[os_window_id] = now
    _apply(boss, os_window_id, target)
