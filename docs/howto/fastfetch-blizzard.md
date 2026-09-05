# Fastfetch: black-metal blizzard (animated logo)

## What it is

Animated WebP logo for fastfetch: a hooded skull (from the reference image) in a blizzard — dithered
texture, diagonal snow streaks, layers/squalls, brightness pulse, optional shaders (invert / RGB
shift) and optional snow accumulation.

The tools are versioned in `files/fastfetch/` and deployed by the module
`modules/user/nix-maid/cli/fastfetch.nix` to `~/.local/share/fastfetch/` and `~/.local/bin/fetch`.
Logos are generated on the fly into `~/.local/share/fastfetch/logos/` (not tracked in git).

## Usage

Quick `fetch` command (randomizer):

```
fetch                            # random variant (dithering x palette x blizzard)
fetch ember                      # ember palette only (or ash / ice)
fetch "#ff0000"                  # custom color — generates its own gradient
fetch --big                      # larger (logo box up to its maximum)
fetch --shader rgb               # chromatic shift (red/cyan)
fetch --shader invert            # negative
fetch --big --shader invert:rgb  # combined
fetch --cover                    # current track cover as the logo
fetch -w 2                       # live mode (refresh every 2 s)
```

zsh defines a `fastfetch` function that delegates to `fetch` (defined in `01-init.zsh`), so
`fastfetch ...` works the same way.

## Generator (`make_blizzard.py`)

```
python3 ~/.local/share/fastfetch/make_blizzard.py       --dither fs --palette ash --color "#39FF14"       --size 900x1130 --shader invert:rgb --accum 1       --storm 1.0 --wind 1.0 --frames 24 --seed 7       --out ~/.local/share/fastfetch/logos/blizzard-custom.webp

--dither  fs|atkinson|sierra|stucki|bayer|noise   (skull texture)
--palette ash|ember|ice   |   --color "#RRGGBB"   (custom gradient)
--shader  none|invert|rgb|invert:rgb
--accum   0 — accumulation off; >0 — growing snow cap
--size    WxH  (default 640x806)
```

Regenerating presets: `~/.local/share/fastfetch/blizzard.sh fs` (or without an argument — all 6
ditherings).

Lua/QuickJS in `format` (experimental, 2.64.0+) is enabled via an overlay (`modules/tools/default.nix`)
— it adds lua to the `fastfetch-unwrapped` buildInputs plus `-DENABLE_LUA` so that `lua:`/`qjs:`
specifiers work.

## Reference

By default REF = /home/neg/pic/necro/8a8c0e082df595deed2ef785f73c3476.jpg. Any image can be passed
via `--ref \<path>` — the pipeline (face-center, crop, dithering, blizzard) applies to any image.

## Storage (XDG)

- scripts: `~/.local/share/fastfetch/`
- logos: `~/.local/share/fastfetch/logos/`
- link: `~/.local/bin/fetch` (on PATH via `~/.local/bin`)
