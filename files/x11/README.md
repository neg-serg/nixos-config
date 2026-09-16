# files/x11 — FVWM "An essence of decay" rice

Sources vendored for the FVWM (X11) session: the rice posted on r/unixporn as "[fvwm] An essence of
decay" (<https://www.reddit.com/r/unixporn/comments/wlscxa/>), i.e. upstream
<https://github.com/syndrizzle/hotfiles>, branch `fvwm`, commit `edc3359` (2022-08-19) — the last
commit of that branch after the post.

Wiring: `modules/user/session/fvwm.nix` behind `features.gui.fvwm.enable` (enabled on odin in
`hosts/odin/default.nix`). The payload package is `packages/decay-rice/default.nix`; the host policy
override that lets odin run an X server lives in `hosts/odin/services/policy.nix`.

## Layout

| Path          | Content                                                                                                                                                                                                                                                                                          |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `rice/home/`  | upstream `$HOME` tree, verbatim: `.fvwm/` (config + titlebar icons), `.scripts/`, `.Xresources`, `.config/{eww,conky,dunst,rofi,jgmenu,tint2,albert,redshift,networkmanager-dmenu,qt5ct,picom.conf,kitty-decay}/`, `.local/share/dockbarx/`, `.icons/`, `.wallpapers/` (wallpaper + lock screen) |
| `rice/share/` | upstream system-wide assets kept by the rice: `icons/Xcursor-Pro-Decay` (cursor theme), `fonts/` (Metropolis + GE Inspira), `jgmenu/MenuIcons`                                                                                                                                                   |
| `decay-gtk/`  | GTK3 port of the Decay palette (`decaycs/gtk3`, variant `decay`, commit `07dbf07`, four years of upstream deprecation notes notwithstanding — it is what the rice used), plus `UPSTREAM.txt`                                                                                                     |

Not vendored (unused by the session, ~100 MB): upstream `usr/share/{slim,albert,macOSBigSur*}` (SLiM
is replaced by greetd; Albert is replaced by a shim), the remaining wallpapers,
`.config/{fish,spicetify,gtk-3.0,starship.toml}` (per-user Wayland config, already nix-managed),
`conky/Izar/preview.png`, `__pycache__`.

## Files we had to add

`dockbarx-themes/` holds the three DockBarX theme archives of the rice, unpacked: `.gitignore`
refuses to track compressed blobs (`*.gz`), while DockBarX reads only `themes/**/*.tar.gz`, so
`packages/decay-rice` packs them back (member names without a `./` prefix, sorted, fixed mtime →
reproducible).

`home/.config/rofi/decay.rasi` is ours: `config.rasi` loads it via `@theme "decay"` and
`screenshot/config.rasi` reads its variables (`bg-col`, `fg-col`, `fg-col2`, `border-col`,
`selected-col`) — upstream's copy of that file was never committed to the dotfiles repo, rofi then
refuses to render the menus ("the variable 'bg-col' … failed to resolve"). The colours are the Decay
palette the rest of the rice uses (kitty `colors.conf`, the eww scss files, `.fvwm/config`).

## Runtime state

The trees nix-maid links are read-only, and files below a *symlinked* parent make `systemd-tmpfiles`
exit 73/CANTCREAT (which fails nix-maid's activation), so the rice's mutable bits are redirected:

| What                                                     | Where                                                                                                                                                          |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| fvwm pid file + FvwmCommand socket                       | `$FVWM_USERDIR` = `$XDG_STATE_HOME/fvwm` (set by `bin/start-fvwm-decay`; `fvwm3 -f ~/.fvwm/config` keeps reading the config from the store)                    |
| `volume.sh` lock file                                    | `$XDG_RUNTIME_DIR/fvwm-volume.lock`                                                                                                                            |
| DockBarX log/state + themes                              | real `~/.local/share/dockbarx` (tmpfiles), theme archives linked file by file                                                                                  |
| DockBarX dock style, window-list style, pinned launchers | dconf `org/dockbarx/dockbarx` (`theme-file=invisible.tar.gz`, `popup-style-file=Decay`, four launchers) — user-db values still win, so the GUI can change them |

## Deviations

The upstream files are tracked byte-identical; `packages/decay-rice/default.nix` applies only the
rewrites below, because NixOS has no FHS tree.

| Upstream                                                                                | NixOS                                                                |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `.scripts/volume.sh`: `/usr/bin/pamixer`                                                | `pkgs.pamixer`                                                       |
| `.scripts/fvwm.sh`: `KDEWM=/usr/bin/fvwm`                                               | `pkgs.fvwm3` (the variable is unused outside KDE)                    |
| `.scripts/dunst/sound-{normal,critical}.sh`: `/usr/share/sounds/Yaru`                   | `pkgs.yaru-theme`                                                    |
| `.config/dunst/dunstrc`: gnome icon dirs, `/usr/bin/dmenu`, `/usr/bin/firefox -new-tab` | `pkgs.papirus-icon-theme`, `rofi -dmenu`, `firefox` (the shim below) |
| `.config/eww/scripts/{getInfo,utils.py}`: `/usr/share/icons/Papirus*`                   | `pkgs.papirus-icon-theme`                                            |
| `.config/kitty-decay/kitty.conf`: `usr/bin/less`                                        | `pkgs.less`                                                          |
| `.config/jgmenu/*.csv`: `/usr/share/jgmenu`, `brave`, `firefox`                         | the package's `share/jgmenu`, `vivaldi` (the browser this host has)  |
| `#!/bin/bash`, `#!/usr/bin/env python`                                                  | `patchShebangs` over the tree; `python` resolves to the shim below   |

`.fvwm/config` itself stays untouched: the one absolute path it contains
(`/usr/lib/mate-polkit/polkit-mate-authentication-agent-1`, `InitFunction`) is provided by a
`systemd.tmpfiles.rules` symlink to `pkgs.mate-polkit`.

Commands upstream calls that nixpkgs does not carry are shimmed in `$out/bin` of `pkgs.decay-rice`,
so the vendored scripts and the fvwm config need no edits:

| Upstream command                           | Shim                                                                                                     |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `python` / `python3`                       | `python3.withPackages [praw requests dbus-python pygobject3 wand]` + `GI_TYPELIB_PATH` for Playerctl/GTK |
| `albert`                                   | `rofi -show drun` (Albert is unpackaged)                                                                 |
| `parcellite`                               | `clipmenud`                                                                                              |
| `light`                                    | `brightnessctl` (the subset `backlight.sh` uses: `light`, `-A`, `-U`, `-S`)                              |
| `firefox` (`Key b A 4`, dunst URL handler) | `vivaldi` — the rice's browser is not installed here; the fvwm config stays verbatim                     |

Window manager version: the config is fvwm3, not fvwm 2.7.0 — a smoke test against both packages
shows fvwm 2.7.0 rejecting the `HM` mouse modifiers of `Mouse 1 W HM drag-n-move` /
`Mouse 3 W HM drag-n-resize` / `Mouse 2 W HM RaiseLower` (titlebar dragging would silently
disappear), while fvwm3 1.1.0 parses the whole config without a single warning. Upstream's
`.xinitrc` therefore becomes `exec fvwm3` in `.config/xinit/xinitrc`.

Known differences that stay: DockBarX keeps its dock theme in dconf, which the repo does not carry —
pick `Decay` once in the dock preferences (the theme files are deployed in
`~/.local/share/dockbarx`); `~/.scripts/shot.sh` still writes to `$HOME/Pictures` as upstream does;
`.Xresources` keeps the upstream `Xft.dpi: 120` of the 1080p laptop the rice was built on.

Screen scale: odin's panel is 3840x2160 while the rice targets 1920x1080, so the session runs
`rice-display` (from `pkgs.decay-rice`) before `fvwm3` and gives a 4K output a 1080p logical desktop
via `xrandr --scale-from`. `.Xresources` keeps the upstream `Xft.dpi: 120`, so the geometry of
`.fvwm/config` and of the eww bar lands exactly where upstream put it.
