# RNNoise virtual microphone (PipeWire)

- Provides a virtual microphone with RNNoise noise suppression via PipeWire filter-chain.
- Global default is enabled; per-host you can disable it explicitly.

Example:

```nix
{
  # Globally (module default is true)
  hardware.audio.rnnoise.enable = true;

  # Per-host override (e.g., hosts/trantor/services/policy.nix)
  hardware.audio.rnnoise.enable = false;
}
```

Notes:

- A user service auto-selects the RNNoise source as the default input on login when enabled.
- You can still manually choose sources in your desktop environment if you prefer.

Docs are English-only (hard rule). SuperCollider live-coding docs live in the private notes repo
(~/notes/music/supercollider/).
