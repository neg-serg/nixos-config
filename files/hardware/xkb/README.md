# Universal Layout (ortho) xkb symbols

OS-side xkb symbols for the [Universal Layout](https://github.com/braindefender/universal-layout) by
braindefender, ortholinear variant. Copied from `layouts/Linux/ortho/xkb/symbols/` at commit
`fcea5bd5e2b2d219a1e4ed583f42361c1c8bf1c1`.

Wellum's firmware sends plain scancodes: the `LANG` key (Caps Lock) expects the OS layout to toggle
between the EN and RU groups, and the symbol layer relies on AltGr (`level3`). Without this layout
the keyboard still types, but `LANG` only acts as a normal Caps Lock.

Files:

- `ul_ortho_combo` -- EN and RU groups in one layout, Caps Lock cycles the groups. This is the file
  Wellum expects; it includes the stock `us`, `ru` and `inet` symbols itself.
- `ul_ortho_eng`, `ul_ortho_rus` -- separate per-language layouts for setups where the desktop
  environment switches languages itself.

Deliberately not wired into the system config yet: the current setup uses `us,ru` with
`hyprland-per-window-layout` and kanata. To enable later, add a NixOS custom layout and make it the
active one, e.g.:

```nix
services.xserver.extraLayouts.ul-ortho = {
  description = "Universal Layout (ortho)";
  languages = [ "eng" "rus" ];
  symbolsFile = ./files/hardware/xkb/ul_ortho_combo;
};
```

Then point the Wayland keyboard layout at `ul-ortho` (Hyprland `kb_layout`), and decide what happens
to the per-window layout daemon and the kanata caps/remap rules -- they overlap with Caps Lock group
switching. Upstream notes that a NixOS build may need the `layout = "..."` line commented out for
the first build.
