______________________________________________________________________

## description: Theme the pleamar shell from the wallpaper

# Theming

Pleamar's colours come from files, not from a settings dialog: a frozen palette in the tree and a
generated skin in `~/.config/pleamar`. The Quickshell workflow this page used to describe (editing
`files/quickshell/Theme/panel.jsonc`, then `quickshell --quit && quickshell &`) went away with that
tree — see "Superseded" at the end.

## What owns colour

- `files/pleamar/lib/palette.plm` — the frozen palette every scene may use: `coal`, `surface`,
  `ink`, `ink.dim`, `accent`. A change here re-themes everything that does not opt into the skin,
  and it needs a commit.
- `~/.config/pleamar/theme.plm` — **generated**: one `library Skin strict { … }` of `skin.*` values
  sampled from the current wallpaper. Never edited by hand and never managed by Nix; a module that
  makes it read-only is a bug.
- `~/.config/pleamar/theme.mode` — `auto` (default), `light` or `dark`; `auto` follows the
  wallpaper's mean luminance.

The contract behind those files (the names, the two samplers, the atomic write, the tests) is
`files/pleamar/scripts/theme/README.md`.

## Re-theme from the wallpaper

```bash
pleamar-theme                      # the cached wallpaper
pleamar-theme --wallpaper ~/pic/wall.png
pleamar-theme --accent '#006FCC'   # force the accent only
```

The script takes the wallpaper from `--wallpaper`, else from
`$XDG_CACHE_HOME/pleamar/wallpaper-path` (canonical), else from the legacy
`$XDG_CACHE_HOME/quickshell-wallpaper-path`, and rewrites `~/.config/pleamar/theme.plm` atomically.
No wallpaper and no `--accent`/`--from-json` is an error and leaves the previous file alone.

## Runtime behaviour

Pleamar re-reads an imported file when it changes, so rewriting `theme.plm` re-themes every running
scene that imports it — no restart, no signal. The trigger is already wired: `pleamar-theme.service`
(oneshot) seeds `theme.plm` from `theme.default.plm` when absent and runs `pleamar-theme`, and the
`pleamar-theme` path unit in `modules/user/nix-maid/gui/pleamar.nix` starts it when either cache
path changes. `theme.mode` is read at run time, so a mode change applies on the next wallpaper
change or on an explicit run with `--mode`.

## Verify

```bash
cargo test --manifest-path packages/pleamar-theme/Cargo.toml --locked   # hermetic suite
bash scripts/dev/check-plm.sh .            # every scene still compiles
```

## Superseded

The Quickshell theming section (the `files/quickshell/` layout, the `Theme/panel.jsonc` colours and
the `quickshell --quit` reload) described a tree that no longer exists; its palette and accent
behaviour is what `pleamar-theme` reproduces for pleamar, and the panel's own tones are now the
frozen ones in `lib/palette.plm`.
