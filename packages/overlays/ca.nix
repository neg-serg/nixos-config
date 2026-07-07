# Content-addressed derivations for rebuild avoidance and trustless
# substitution. Large user-facing apps benefit most — identical outputs
# skip rebuild when input derivation changes (version bumps, build tweaks).
_: _: prev:
  let
    ca = drv: drv.overrideAttrs (_: { __contentAddressed = true; });
  in
  {
    # Browsers
    vivaldi = ca prev.vivaldi;

    # Communication
    telegram-desktop = ca prev.telegram-desktop;

    # LLM
    ollama = ca prev.ollama;

    # Gaming
    steam = ca prev.steam;
    openmw = ca prev.openmw;

    # Emulation
    retroarch = ca prev.retroarch;
    qemu_kvm = ca prev.qemu_kvm;

    # Media & graphics
    spotify = ca prev.spotify;
    darktable = ca prev.darktable;

    # Windows compat
    bottles = ca prev.bottles;
  }
