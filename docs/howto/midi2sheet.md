# midi2sheet: MIDI → sheet music in PDF

`midi2sheet` is a CLI tool (package `pkgs.neg.midi2sheet`) that turns a MIDI file into a piano PDF
score: the right hand (≥ C4) on the upper staff, the left on the lower. Rendering is done by MuseScore
Studio in headless mode (under Xvfb), so the command works without a GUI and without an open display.

## Usage

```bash
midi2sheet input.mid                    # -> input.pdf next to the source
midi2sheet input.mid -o out.pdf         # explicit output path
midi2sheet input.mid --mscz             # additionally save input.mscz (editable MuseScore source)
midi2sheet input.mid --split 55         # hand-split threshold (MIDI note number, default 60 = C4)
```

The score title is taken from the input file name (without the extension). When run with `--mscz`, a
.mscz appears next to the PDF — it can be opened and edited in MuseScore.

## How it works

1. `split.py` (pure Python, no dependencies) parses MIDI (including running status), splits the notes
   by pitch threshold into two tracks, and writes a format-1 MIDI with the "Piano" program.
1. MuseScore imports the split MIDI (detects time/key signature itself, lays the notes out into
   measures, ties long notes) and saves `.mscz`.
1. `patch_title.py` rewrites `workTitle` in the mscz (MuseScore takes the title from the file name;
   there is no separate CLI flag).
1. The final PDF is exported from the patched mscz.

MuseScore for the package comes from "clean" `inputs.nixpkgs.legacyPackages` — the config's global
overlays change the derivation hash of `pkgs.musescore`, which would force a full source build; the
regular build is already in the store.

## Open/edit mscz

```bash
nix shell nixpkgs#musescore -c musescore file.mscz
```

## Notes

- Time signature and key signature are MuseScore's output of the import, not data from the MIDI (MIDI
  usually has the default 4/4). If something else is needed — edit in MuseScore.
- Quantization: MuseScore's import keeps the fine rhythm of transcriptions (down to 32nds/64ths); for
  "dirty" MIDI that is hard to read — run it through `midi-transcribe --post quantize` before the
  conversion.
