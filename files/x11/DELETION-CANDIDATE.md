# Deletion candidate — `files/x11/`

Marked 2026-10-19. Not wired into the configuration: no `.nix`, `.lua` or `.md` in the repo
references `files/x11/`, so nothing here reaches a generation.

What is actually on disk: eight icons from an unpacked X11/conky rice —
`rice/home/.icons/tmp/{volume,brightness}-*.svg` (~13 KB total). The `tmp/` path and the absent
`conky` config in the tree say it was dropped here while extracting that rice and left behind. This
host runs Hyprland, and its status bar is pleamar, so there is no consumer for a conky setup.

Keep only if those eight icons are wanted somewhere (they would belong under `files/gui/` or
`files/shell/` with a real link in nix-maid). Otherwise the whole directory goes:

```sh
rm -r files/x11
```

The SVGs themselves are untracked; the only tracked file under this path is this marker (and the
`files/README.md` line that points here).
