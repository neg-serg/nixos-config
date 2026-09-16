# dsh keymap: rebinding the TUI keys

> Tianshu generation: the `tui` profile now runs dsh-TUI — see
> [dsh-tui-profile.md](./dsh-tui-profile.md). The keymap patch described here is dormant while
> dsh-TUI is installed; dsh-TUI carries its own keymap layer.

The Tianshu TUI's built-in keys are **not** hardcoded: `createBuiltinActions()` returns a
declarative action table

```js
{
  id: "app.quit",
  keys: [{ name: "ctrl_q" }],
  phase: "early",
  category: "<category>",   // localized label shown in the overlay
  hint: "<hint>",
  keymapOrder: 50,
  run: (ctx) => ctx.requestExit(),
}
```

consumed twice — by `ActionRegistry` for dispatch and by `projectKeymapEntries()` for the `Ctrl+.`
overlay. That makes **rebinding by action id** the right seam: one override moves the key and the
overlay follows, with no dispatch-time translation to reason about.

Upstream reads no keymap; `dsh-tui-ru.nix` patches it in with three `FIXES` entries in
`dsh-tui-ru-assets/patch.mjs` (`tui-keymap-helper`, `-overlay`, `-registry`): a helper inserted next
to the action table, and the two consumption sites wrapped in `applyUserKeymap(...)`.

## The file

`~/.dsh-tui/keymap.json` (same directory as `prefs.json` and `themes/`), or `$DSH_TUI_KEYMAP`.

```json
{
  "app.quit": "ctrl+y",
  "palette.toggle": ["ctrl+p", "alt+p"],
  "session.new": []
}
```

| Value                 | Effect                          |
| --------------------- | ------------------------------- |
| `"ctrl+y"`            | replace the binding             |
| `["ctrl+p", "alt+p"]` | several bindings for one action |
| `[]`                  | unbind the action entirely      |

A key that is not in the file keeps its built-in binding, and an action id that does not exist is
ignored — the file is a patch, not a replacement.

### Key vocabulary

The decoder names keys as `ctrl_<letter>`, `shift_tab`, `return`, `escape`, `tab`, `space`, arrows,
`home`/`end`, `pageup`/`pagedown`, `backspace`, `delete`, and matches printable keys by `char`
(uppercase = shift). The specs you can write map onto exactly that:

| Spec                                                                                | Binding                                                |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `ctrl+n`, `ctrl+.`                                                                  | `{ name: "ctrl_n" }`, `{ name: "ctrl_." }`             |
| `ctrl+enter`                                                                        | `{ name: "ctrl_return" }`                              |
| `alt+w`                                                                             | `{ char: "w", meta: true }`                            |
| `shift+tab`                                                                         | `{ name: "shift_tab" }`                                |
| `enter` / `return`, `esc`, `tab`, `space`                                           | the named key                                          |
| `up`, `down`, `left`, `right`, `home`, `end`, `pgup`, `pgdn`, `backspace`, `delete` | the named key                                          |
| `a`, `A`                                                                            | `{ char: "a" }` / `{ char: "A" }` (uppercase is shift) |

`ctrl+shift+<letter>` and `alt+shift+<letter>` are **rejected**: the decoder folds them into
`ctrl_<letter>` / the uppercase char, so they cannot name a distinct binding, and accepting them
would silently collapse onto another key.

## Safety

`ActionRegistry.register()` validates key conflicts and **throws** on a clash, so a bad map could
kill startup. `applyUserKeymap()` therefore:

- pre-validates with `validateActionConflicts()` and **returns the built-ins unchanged** when the
  map would conflict — a bad keymap costs the rebind, never the session;
- keeps an action's built-in binding when its spec is a typo;
- ignores a missing, malformed or non-object file entirely (no keymap → the table is returned by
  reference, untouched).

## Discovery: no which-key needed

A which-key panel exists to show what a **leader key** can be followed by. This TUI has no leader
system — every binding is a single chord — so there is nothing to expand. The discovery surface is
already there and is not redundant: **`Ctrl+.`** opens the keymap overlay, and because the overlay
projects the same action table this patch rewrites, it shows your bindings. `keymapOrder`,
`category` and `hint` in the table are the overlay's data (their values are localized UI copy).

## Verification

`modules/user/nix-maid/apps/dsh-tui-ru-assets/keymap.test.mjs` — 60 assertions: the three anchors
and their probes, the patcher mechanics on a fixture (apply, parse, re-run byte-identical, exactly
one helper and exactly two wrapped call sites), the whole spec vocabulary and its rejections, rebind
/ multi-bind / unbind by id, the non-mutation of the input table, typo handling, conflict fallback,
and malformed-JSON fallback.

Runtime, in a PTY against the real bundle:

| Case                                                  | Result                                                                             |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `{"app.quit": "ctrl+y"}`, send `Ctrl+Q`               | the TUI keeps running (exit 124) — the old key is rebound away                     |
| same keymap, send `Ctrl+Y`                            | the TUI exits (exit 0)                                                             |
| `{"app.quit": "ctrl+n"}` (clashes with `session.new`) | the TUI starts normally and `Ctrl+Q` still quits — the fallback kept the built-ins |
