# Hotkey backlog — what is still open

The 2026-10-14 audit of emacs/vim-friendly keys (per-surface reports for shell, TUI, editors/web,
quickshell, vicinae and the global layers) landed most of its findings; the canon and the RU-layout
rules live in [hotkeys-ru-layout.md](./hotkeys-ru-layout.md). This file keeps the open items so the
list survives the audit scratch files, with the evidence and the one-line fix for each.

## Landed (orientation)

- shell: `inputrc` vi + vi-insert emacs layer; zsh viins-emacs layer with `^Y` = yank and zoxide
  moved to `^G` (`files/shell/zsh/04-bindings.zsh`, `04-fzf.zsh`); fzf `Alt-j/k`
  (`modules/user/nix-maid/cli/search.nix`).
- CLI/TUI: khal `export = x` / `delete = D`, mutt pager `C-d` / `C-u`, swayimg
  `C-n/C-p/C-a/C-e/C-b/C-f`, zellij `pane`/`move` entries with RU duplicates plus `Ctrl [` in every
  mode, espanso off `Alt+Space`.
- editors: nvim insert-mode `<C-a>` is `<C-o>0`, matching the command line.
- browser: the new-tab tiles take `j/k`, `Enter` opens the selection, `/` focuses the search field.
- quickshell: MusicPopup joined the overlay manager and closes on `Esc`; named overlays (calendar,
  weather) and the media/volume IPC are exposed for binds; vicinae runs the patched hybrid vim/emacs
  keybinding set.

## Open

| Item                            | Evidence                                                                                                                                                     | Fix                                                                                                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| dsh key remap: nothing to wire  | no `shortcuts:` block is needed: the schema takes `dsh-tui.shortcuts.<id>` (plugin.js:1172); the editor has no emacs motions and `/vim` is session state     | leave the panel combos alone; remap via `/settings -> shortcuts` on a real conflict                                                                                          |
| Obsidian vim mode               | the deployed vault is gated by `features.apps.obsidian`, and the `apps` domain is filtered out on trantor; the working vault is `~/notes`, outside this repo | enable `vimMode` and version a `.obsidian.vimrc` in the real vault (needs a write outside the repo)                                                                          |
| Quickshell bar keyboard         | `files/quickshell/Bar/**` carries no `Keys`/`Shortcut`                                                                                                       | add `Keys.onPressed` for `C-n/C-p` to walk the modules and `Enter` to open; layer surfaces are not keyboard-interactive today, so the interaction model is a design decision |
| Quickshell transport binds      | `IPCHandlers.qml` now exposes the calendar/weather/media/volume calls; `hyprland.lua` binds calendar, weather and play/pause                                 | add binds for `mediaNext`, `mediaPrev` and `volumeStep(±)`                                                                                                                   |
| Quickshell panels, toasts, lock | `Components/PanelWithOverlay.qml:96` (only `k`/`d`/`Esc`), `Notifications/NotificationOverlay.qml`, `greeter/lock/LockContent.qml:739+`                      | add `j/k/Enter` and the emacs editing set; remember `Ctrl+A` is Qt's select-all in the lock field                                                                            |
| ncpamixer arrows                | `files/media/ncpamixer.conf:14-18` binds `k`/`j`; the key-name syntax for arrows and `Ctrl`-chords is undocumented locally                                   | confirm the tokens against upstream before touching a live mixer config                                                                                                      |
| rustmission `gg`/`G`            | `files/config/rustmission/keymap.toml` already has vim + emacs navigation and Home/End                                                                       | only if the parser supports key sequences and upstream has the actions                                                                                                       |
| vicinae `move-up`/`move-down`   | `modules/user/nix-maid/apps/vicinae.nix:106-125` leaves the panel move actions unreachable                                                                   | bind them to `Ctrl+Shift+Up/Down` once the action ids are confirmed against the installed build                                                                              |
| neru hints                      | `files/neru/config.toml` (hints are typed by label; `kb_layout_to_use = "us"`)                                                                               | needs an upstream mode for `Tab`/arrow navigation                                                                                                                            |
| kanata vs `Caps_Lock`           | `files/gui/hypr/hyprland.lua` binds `Caps_Lock`, while `files/cli/kanata/kanata.kbd:23-29` maps caps to `LeftCtrl`                                           | the toast is now documented as the no-kanata fallback; remove the bind if kanata is retired                                                                                  |
| iris `j/k`                      | `files/iris/config.toml:52-56`; the zsh wrapper is disabled (`files/shell/zsh/.zshrc:1-4`)                                                                   | add `Ctrl-j/k` when iris is switched back on                                                                                                                                 |
| lazytail keys                   | `files/lazytail/config.yaml` has no key section                                                                                                              | upstream feature request; note it in the tool's docs meanwhile                                                                                                               |
