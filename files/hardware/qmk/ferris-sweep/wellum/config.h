#pragma once

// Z and / (the bottom outer keys) are Shift mod-taps: tap for the letter, hold
// for Shift. They are the only tap-hold keys in this keymap — the rest is plain
// keys, layer keys and one-shot mods — so this policy is tuned for them.
#define TAPPING_TERM 200

// Shift needs the other key to be tapped through while the mod-tap is still
// down (Permissive Hold) and only across hands (Chordal Hold). Same-hand
// chords — Z+X, /+. — settle as letters right away instead of Shift.
#define PERMISSIVE_HOLD
#define CHORDAL_HOLD
