______________________________________________________________________

## description: Configure Hyprland keybindings

# Hyprland Keybindings

## Configuration File

All keybindings live in one Lua file:

`files/gui/hypr/hyprland.lua`

Hyprland 0.55+ auto-detects `~/.config/hypr/hyprland.lua` and ignores the legacy `hyprland.conf`, so
the old `bindings/apps.conf`, `bindings/special.conf` and `bindings/wm.conf` files are gone. The Lua
file is read into the Nix store at build time by `modules/user/nix-maid/hyprland/main.nix` and
linked to `~/.config/hypr/hyprland.lua`.

## Syntax

```lua
hl.bind(MODS .. "+KEY", hl.dsp.<dispatcher>({ ... }), { OPTIONS })
```

Modifiers are Lua locals declared at the top of the file:

| Local | Key     |
| ----- | ------- |
| `M4`  | `SUPER` |
| `M1`  | `ALT`   |
| `C`   | `CTRL`  |
| `SH`  | `SHIFT` |

Join them with `..` and `"+"`, e.g. `M4 .. "+" .. SH .. "+c"`.

Dispatchers are `hl.dsp.*` calls; the config uses `exec_cmd`, `focus`, `layout`, `submap`,
`workspace.move` and `window.{close,cycle_next,drag,float,fullscreen,fullscreen_state,move,resize}`.

The optional third argument holds bind options: `{ locked = true }`, `{ repeating = true }`,
`{ mouse = true }`, `{ release = true }`.

## Examples

### Launch application:

```lua
hl.bind(M4 .. "+Return", hl.dsp.exec_cmd("kitty"), { locked = true })
hl.bind(M4 .. "+" .. SH .. "+m", hl.dsp.exec_cmd("~/.local/bin/main-menu"))
```

### Window control:

```lua
hl.bind(M4 .. "+Escape", hl.dsp.window.close())
hl.bind(M4 .. "+r", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(M4 .. "+" .. SH .. "+f",
  hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
```

### Workspaces and submaps:

```lua
hl.bind(M4 .. "+1", hl.dsp.focus({ workspace = "1" }))
hl.bind(M4 .. "+mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(M4 .. "+minus", hl.dsp.submap("tiling"))
```

Toggling floating windows uses `hl.dsp.window.float({ action = "toggle" })` (see the `special`
submap); submaps are declared with `hl.define_submap(name, reset_key, function() ... end)`.

## Apply Changes

The file is linked from the Nix store, so a repo edit needs a rebuild first:

```bash
nh os switch /etc/nixos#odin --option substitute false
```

Then reload the running compositor:

```bash
hyprctl reload
```

## Debug

Check active bindings:

```bash
hyprctl binds
```
