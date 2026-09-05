# Free Windows VSTs for bridging on Linux (yabridge / Carla wine bridge)

> Collected by a subagent on 2026-08-20 (official sources, GitHub API). yabridge (nixpkgs) is 64-bit
> only; 32-bit plugins are excluded. Plugins with native Linux builds are marked — they do not need to
> be bridged.

## Top candidates (Windows-only, 64-bit, headless-friendly)

| Plugin                | Type                        | Format      | Download (official)                      | Size    | Notes                                                         |
| --------------------- | --------------------------- | ----------- | ---------------------------------------- | ------- | ------------------------------------------------------------- |
| Sforzando (Plogue)    | sampler/SFZ player          | VST2/VST3   | plogue.com/products/sforzando.html       | ~3 MB   | free SFZ player; GUI needed once to load banks                |
| Tx16Wx                | sampler                     | VST2/VST3   | tx16wx.com                               | ~30 MB  | pro sampler, slicing                                          |
| ReaPlugs (Cockos)     | FX set (ReaEQ, ReaComp…)    | VST2 32/64  | reaper.fm/reaplugs                       | ~5 MB   | officially tested under WINE — the most reliable candidate    |
| Valhalla Supermassive | reverb/delay                | VST2.4/VST3 | valhalladsp.com                          | ~20 MB  | the best free reverb, v5.x                                    |
| TDR Nova              | dynamic EQ                  | VST2/VST3   | tokyodawn.net/tdr-nova                   | ~10 MB  | OpenGL UI (usually fine under wine)                           |
| TDR Kotelnikov        | compressor                  | VST2/VST3   | tokyodawn.net/tdr-kotelnikov             | ~10 MB  | mastering compressor                                          |
| Xfer OTT              | multiband compressor        | VST2/VST3   | xferrecords.com/free-downloads/ott       | ~2 MB   | the iconic "OTT" sound; site behind Cloudflare — download in a browser |
| Klanghelm IVGI        | saturation                  | VST2/VST3   | klanghelm.com/contents/products/IVGI.html | ~2 MB  | tiny, headless OK                                             |
| Voxengo SPAN          | analyzer                    | VST2/VST3   | voxengo.com/product/span                 | ~3 MB   | for monitoring in Carla                                       |
| iZotope Vinyl         | lo-fi/vinyl                 | VST2/VST3   | izotope.com/en/products/vinyl.html       | ~30 MB  | for generative music                                          |
| Kairatune             | VA synth                    | VST2 64     | futucraft.com/kairatune                  | ~3 MB   | zip install = headless-friendly                               |
| K1v (KORG)            | M1 emulation                | VST2 64     | korg.com/us/products/software/k1v        | ~10 MB  | KORG ID, free; page may 404 from RU                           |
| Kilohearts Essentials | 30+ FX                      | VST2/VST3   | kilohearts.com/products/kilohearts_essentials | ~400 MB | installer-based                                               |

## Do not bridge (native Linux builds exist)

Vital, Surge XT, Dexed, OB-Xd, Odin 2, TAL-NoiseMaker, TAL-U-NO-LX, Tyrell N6, Graillon 3 (free),
Rough Rider 3 — all have Linux versions and are installed as packages (Vital/Surge/Dexed/OB-Xd are
already in nixpkgs).

## MS-20 clones

No free MS-20 clone with an official source was found. Closest verified emulations: K1v (M1),
TAL-U-NO-LX (Juno-106), OB-Xd (Oberheim), Dexed (DX7).

## Links

All links are in the table above (verified by the subagent on 2026-08-20). Plogue and Xfer pages
block bots (403/Cloudflare) — download in a browser.
