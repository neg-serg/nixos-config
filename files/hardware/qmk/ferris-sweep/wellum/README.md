# Wellum keymap for the Ferris Sweep

[Wellum](https://github.com/braindefender/wellum) is a 34/36-key layout by braindefender. These
files are a verbatim copy of `firmware/qmk` from braindefender/wellum at commit
`2b0fd86a1996b4ce7b4f33e80f9d557120f5258f` (README version v3.1.1); `keymap-34.c` is renamed to
`keymap.c`.

The copy drops onto `ferris/sweep` unchanged:

- The Sweep implements `LAYOUT_split_3x5_2` in the standard `split_3x5_2` element order (three 5-key
  rows per half, then thumb keys in the order left outer, left inner, right inner, right outer),
  which is exactly the order the Wellum 34 keymap already uses.
- 34 keys tall, matching the Sweep exactly.

Install (clones QMK when needed, copies this keymap in, compiles it, then flashes both halves):

```
just wellum
```

The default build targets an RP2040 Pro Micro class controller through QMK's `CONVERT_TO=rp2040_ce`
converter (Sea-Picro, Elite-Pi, RP2040 Pro Micro clones; the converter adds VBUS-based master
detection), producing `.build/ferris_sweep_wellum_rp2040_ce.uf2`. Overrides:

- `WELLUM_CONVERT=sparkfun_pm2040` for the SparkFun Pro Micro RP2040.
- `just wellum-avr` (or `WELLUM_CONVERT=`) for an AVR Pro Micro/Elite-C build; add
  `WELLUM_BOOTLOADER=dfu` for an Elite-C.

`just wellum-build` stops after compiling. Everything runs through `scripts/dev/qmk-wellum.sh`,
which uses the pinned QMK devshell from this repo and `$QMK_HOME` (default `~/src/qmk_firmware`).
Flashing prompts for each half's bootloader (BOOTSEL on RP2040, reset button or bootmagic on the Pro
Micro) and waits for the device.

Wellum expects the OS-side [Universal Layout](https://github.com/braindefender/universal-layout) for
the `LANG` (Caps Lock) language toggle and the AltGr symbol layer; the firmware sends plain
scancodes and does not switch the OS layout itself.
