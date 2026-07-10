# hypr-focus

Hyprland focus history tracker and window management CLI. A fast Rust replacement for the Python `hypr-focus-hist` daemon, with a full suite of window management commands built in.

The binary is named `hypr-focus` in the Nix store. A symlink named `hypr-focus-hist` in `~/.local/bin/` points to it for backward compatibility with existing keybindings and scripts.

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `daemon` | Start background focus tracking | `hypr-focus daemon` |
| `switch` | Focus the previously focused window | `hypr-focus switch` |
| `workspace <ID>` | Jump to a workspace by ID or name | `hypr-focus workspace 3` |
| `move-to-workspace <ID> [--follow]` | Move the active window to a workspace, optionally follow | `hypr-focus move-to-workspace 5 --follow` |
| `float` | Toggle floating for the active window | `hypr-focus float` |
| `fullscreen` | Toggle fullscreen for the active window | `hypr-focus fullscreen` |
| `pin` | Toggle pin across workspaces | `hypr-focus pin` |
| `layout [master\|dwindle]` | Set or toggle the layout | `hypr-focus layout dwindle` |
| `orientation` | Cycle master orientation | `hypr-focus orientation` |
| `split-ratio <VAL>` | Adjust or set the master split ratio | `hypr-focus split-ratio +0.1` or `hypr-focus split-ratio 0.6` |
| `swap-master` | Swap the active window with the master window | `hypr-focus swap-master` |
| `add-master` | Add the active window to the master list | `hypr-focus add-master` |
| `remove-master` | Remove the active window from the master list | `hypr-focus remove-master` |
| `toggle-split` | Toggle dwindle split direction | `hypr-focus toggle-split` |
| `preselect <l\|r\|u\|d>` | Preselect a split direction for the next window | `hypr-focus preselect r` |

## Daemon Setup

The daemon listens to Hyprland IPC events, tracks window focus history (LRU, max 20 entries), and writes the previous window address to a state file for the `switch` command. On connection loss it automatically reconnects after 2 seconds. Logs go to `/tmp/hypr-focus-hist.log`.

### Hyprland autostart (hyprland.lua)

```lua
hl.exec_cmd("hypr-focus daemon")
```

### systemd user service

```ini
[Unit]
Description=Hyprland Focus History Daemon
PartOf=graphical-session.target

[Service]
ExecStart=%h/.local/bin/hypr-focus daemon
Restart=always

[Install]
WantedBy=graphical-session.target
```

## Hyprland Keybindings

Keybinding examples using the hyprland.lua DSL:

```lua
-- Focus history
hl.bind(M4 .. "+Tab", hl.dsp.exec_cmd("hypr-focus switch"))

-- Layout toggle
hl.bind(M4 .. "+" .. C .. "+space", hl.dsp.exec_cmd("hypr-focus layout"))

-- Window operations
hl.bind(M4 .. "+" .. C .. "+f", hl.dsp.exec_cmd("hypr-focus float"))
hl.bind(M4 .. "+" .. SH .. "+f", hl.dsp.exec_cmd("hypr-focus fullscreen"))
hl.bind(M4 .. "+" .. SH .. "+p", hl.dsp.exec_cmd("hypr-focus pin"))

-- Workspace navigation
hl.bind(M4 .. "+" .. C .. "+1", hl.dsp.exec_cmd("hypr-focus workspace 1"))
hl.bind(M4 .. "+" .. C .. "+2", hl.dsp.exec_cmd("hypr-focus workspace 2"))

-- Move window to workspace and follow
hl.bind(M4 .. "+" .. C .. "+" .. SH .. "+1", hl.dsp.exec_cmd("hypr-focus move-to-workspace 1 --follow"))

-- Master layout controls
hl.bind(M4 .. "+" .. SH .. "+m", hl.dsp.exec_cmd("hypr-focus swap-master"))
hl.bind(M4 .. "+" .. C .. "+m", hl.dsp.exec_cmd("hypr-focus add-master"))
hl.bind(M4 .. "+" .. C .. "+" .. SH .. "+m", hl.dsp.exec_cmd("hypr-focus remove-master"))
hl.bind(M4 .. "+" .. SH .. "+s", hl.dsp.exec_cmd("hypr-focus toggle-split"))
hl.bind(M4 .. "+" .. C .. "+s", hl.dsp.exec_cmd("hypr-focus orientation"))

-- Split ratio
hl.bind(M4 .. "+" .. C .. "+equal", hl.dsp.exec_cmd("hypr-focus split-ratio 0.5"))
hl.bind(M4 .. "+" .. C .. "+plus", hl.dsp.exec_cmd("hypr-focus split-ratio +0.05"))
hl.bind(M4 .. "+" .. C .. "+minus", hl.dsp.exec_cmd("hypr-focus split-ratio -0.05"))

-- Preselect split direction
hl.bind(M4 .. "+" .. SH .. "+h", hl.dsp.exec_cmd("hypr-focus preselect l"))
hl.bind(M4 .. "+" .. SH .. "+l", hl.dsp.exec_cmd("hypr-focus preselect r"))
hl.bind(M4 .. "+" .. SH .. "+k", hl.dsp.exec_cmd("hypr-focus preselect u"))
hl.bind(M4 .. "+" .. SH .. "+j", hl.dsp.exec_cmd("hypr-focus preselect d"))
```

## Building

```bash
nix build .#neg.hypr-focus
```

## Logs

The daemon writes a timestamped log to `/tmp/hypr-focus-hist.log`. Desktop notifications (via `notify-send`) alert on connection loss.

## License

MIT
