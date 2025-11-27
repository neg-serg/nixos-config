# Cursor Notes

- Current theme: Alkano-aio, size 23 set in `home/modules/user/theme/default.nix` (XCURSOR/HYPRCURSOR/GTK/Stylix all aligned).
- Extracted pointer frames: `docs/cursors/alkano/left-main_000.png`…`left-main_029.png` with metadata `docs/cursors/alkano/left-main.conf` (sizes/hotspots) plus reports `docs/cursors/alkano/color-summary.txt` (color ➜ size) and `docs/cursors/alkano/hotspot.txt` (hotspot pixel, top 3×3 color per size).
- Hotspots: sizes 16–25 use (1,1); 28–37 use (3,3); 39–48 use (4,4) as xhot/yhot (see `left-main.conf`).
- Dominant hotspot colors (alpha ≥ 0.2 in 3×3) ➜ sizes: `fcfcfcce`: 28,36,39,47; `202020ce`: 30,34,35,41,45,46; `202020cc`: 33,44; `192529cc`: 29,40; `182528ce`: 31,42; `002000cc`: 32,43; `000000ce`: 37,48; `fbfbfbcc`: 16,24; `0021006a`: 20; `2121216a`: 21; `2121216c`: 23; `1826286a`: 17; `b2a53fed`: 18; `65a230ed`: 19; `aa2525ed`: 22; `aaaaaaed`: 25.
- Re-generate locally: `nix build -E 'with import <nixpkgs> {}; callPackage ./home/modules/user/theme/alkano-aio.nix {}' -o /tmp/alkano && nix shell nixpkgs#xcur2png -c xcur2png -d docs/cursors/alkano -c docs/cursors/alkano/left-main.conf /tmp/alkano/share/icons/Alkano-aio/cursors/left-main`.
