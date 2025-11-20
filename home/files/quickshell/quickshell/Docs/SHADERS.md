# Quickshell Shaders and Wedge Clip

This document summarizes how shaders are used in this setup, how the subtractive triangular wedge
works, and how to build/debug the shader bundle. For the Russian translation see `SHADERS.ru.md`.
triangular "wedge" clip works, and how to build and debug the shaders.

______________________________________________________________________

Quick Checklist

- Build shaders: `nix shell nixpkgs#qt6.qtshadertools -c bash -lc 'scripts/compile_shaders.sh'`
- Visibility test: `QS_ENABLE_WEDGE_CLIP=1 QS_WEDGE_DEBUG=1 QS_WEDGE_SHADER_TEST=1 qs` (must see
  magenta)
- If no magenta: move bars to Overlay (auto in debug), check logs with `debugLogs: true`
- If wedge not obvious: set `QS_WEDGE_WIDTH_PCT=60` to temporarily widen the seam
- Ensure sources hide: `ShaderEffectSource.hideSource === Loader.active`; raise clip z (e.g.
  `z: 50`) during debug
- Panel transparency affects perceived wedge strength — see `Docs/PANELS.md`
