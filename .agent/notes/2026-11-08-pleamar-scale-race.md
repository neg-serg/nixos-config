# Pleamar scenes load before the compositor applies scale 2

Date: 2026-11-08

## Symptom

After the Hyprland restart at 03:35 the bar had only its left row. The right row (media, mic,
volume, Genelec) was missing and the bar looked laid out for a 3840-wide surface on a 1920-wide
panel.

## Evidence

- `journalctl --user -u pleamar-bar -b`: `render · surface 0 on DP-2 · 3840×35 · scale 1`, then five
  seconds later `surface 0: scale 1 → 2`; the physical frames are 3840×70, so the settled logical
  surface is 1920×35.
- `pleamar --say bar describe`: `panel 1920×35 · scale 2`, but `strip_hover` was `at 0,10 3840×25`
  and the right row sat at x≈3832, outside the panel (the describe output culls off-panel zones, so
  the row disappeared).
- `pleamar --say bar "fact screen.width"` returned 1920 after the scale event: the fact had been
  corrected, the geometry compiled from it at load had not.
- Restarting `pleamar-bar.service` at 06:04 (compositor already at scale 2) gave
  `strip_hover 1920×25`, the right row at 1314..1916 and a passing `just pleamar-geometry`.

## Cause

The layer surfaces are configured once at 3840×35 / scale 1 before `wp_fractional_scale` reports 2.
Pleamar updates the `screen.width` / `screen.height` facts when the scale changes, but zones and
rows compiled from those values keep the load-time 3840 geometry. A scene is only correct when it is
loaded after the compositor has settled at its real scale.

## Recovery

After a compositor restart or any scale change, reload the scenes: `just pleamar-restart` (bar,
launcher, notifications, osd, toast). The lock scene is started on demand, after the scale is
settled, so it is not in that list.

## Repo fix made

`scripts/dev/check-pleamar-geometry.sh` treated the bartip header
(`bartip · panel 1920×104 · scale 2`, no `(screen N)` suffix) as part of the main surface, so a
multi-line bartip text line (`Loaded: 0:10»`) was parsed as a zone and failed the bounds/overlap/gap
checks. The header test now keys on `· panel` and only `main` zones are parsed.

## Upstream

Pleamar should re-layout `screen.width`-dependent geometry on `ToRender::Scale` / `SheetSize`, or
scenes should avoid load-time `screen.width` for placement. Not patched locally; the pin is 0.7.17
(2026-11-05).
