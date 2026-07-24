# TidalCycles Live Coding on NixOS

## Architecture

```
You (nvim .tidal) → GHCi (tidal-ghci) → OSC :57120 → SuperDirt (sclang) → JACK → RME HDSPe
                                                ↑
                                          Dirt-Samples
```

- **TidalCycles**: Haskell pattern language — you write patterns like `d1 $ sound "bd sn"`
- **SuperDirt**: SuperCollider-based synthesis engine — receives OSC, plays audio
- **PipeWire JACK**: Low-latency audio routing (48kHz, 128 frames quantum)

## Quick Start

```bash
# 1. Open a Tidal session
just tidal

# 2. In nvim, press Ctrl+Enter to launch SuperDirt + GHCi
#    Wait for "SuperDirt: listening to Tidal on port 57120"

# 3. Type a pattern and press Alt+Enter to send:
d1 $ sound "bd sn"

# If you hear a kick and snare → everything works!
```

## Keybindings (nvim)

| Key | Action |
|-----|--------|
| `Ctrl+Enter` | Launch Tidal + SuperDirt |
| `Ctrl+Shift+Enter` | Quit Tidal session |
| `Alt+Enter` | Send current line to Tidal |

## Troubleshooting

### No sound

1. Check PipeWire: `pw-cli ls Node | grep SuperDirt`
2. Patch audio: `just tidal-patch` (opens pw-audioshare)
3. Check OSC: `just tidal-rt` to see if scsynth is running

### "ghci not found"

Run `which tidal-ghci` — should be in PATH after rebuild. If not, deploy first: `just deploy`

### Xruns / crackling

Increase PipeWire quantum temporarily: create `~/.config/pipewire/pipewire.conf.d/99-tidal.conf`:

```json
context.properties = {
    default.clock.quantum = 512
}
```

Then `systemctl --user restart pipewire`

### SuperDirt can't find samples

Check symlink: `ls ~/.local/share/SuperCollider/downloaded-quarks/Dirt-Samples`

## Basic Patterns

```haskell
-- Simple patterns
d1 $ sound "bd sn bd sn"       -- kick, snare alternating
d2 $ sound "hh*4"              -- hi-hat 4x per cycle
d3 $ sound "arpy" # speed 2    -- pitched sample, double speed

-- Euclidean rhythms
d1 $ sound "bd(3,8)"           -- 3 hits in 8 steps

-- Effects
d1 $ sound "bd" # gain 1.5 # room 0.5 # size 0.8 # shape 0.3

-- Sample library: bd, sn, hh, bass, arpy, cp, feel, ...
```

## Sample Library

Samples are installed to `/nix/store/<hash>-dirt-samples/share/Dirt-Samples/`.

Symlinked to `~/.local/share/SuperCollider/downloaded-quarks/Dirt-Samples/` for SuperDirt.

## MIDI

Install `tidal-midi` is included. Add to your Tidal session:

```haskell
import Sound.Tidal.MIDI.Output

-- Create a MIDI connection
midi <- midiname "your-midi-device"
d1 $ midi $ note "c d e f"
```

## Files

| Path | Purpose |
|------|---------|
| `~/.config/SuperCollider/superdirt_startup.scd` | SuperDirt boot script |
| `~/.config/SuperCollider/boot_noop.scd` | Minimal boot (no SuperDirt) |
| `~/.config/tidal/BootTidal.hs` | GHCi startup (OSC config) |
| `~/.local/share/SuperCollider/downloaded-quarks/Dirt-Samples` | Sample library |

## Related

- [TidalCycles docs](https://tidalcycles.org/docs/)
- [SuperDirt](https://codeberg.org/musikinformatik/SuperDirt)
- [tidal.nvim](https://github.com/grddavies/tidal.nvim)
