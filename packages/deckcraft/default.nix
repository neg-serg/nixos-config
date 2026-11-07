# DeckCraft — presentations and slide shows (deck editor, speaker view,
# PPTX/ODP interchange, PDF export) plus its `deckcraft-cli` companion.
#
# Upstream: https://github.com/storytold/deckcraft (MIT OR Apache-2.0). Built
# from the release tag through lib/mkCraftApp.nix. ALSA is linked by the media
# playback backend (cpal/alsa-sys), not dlopen'ed.
{
  neg,
  alsa-lib,
  ...
}:
neg.functions.mkCraftApp {
  name = "deckcraft";
  version = "0.16.0";
  hash = "sha256-/8GoID6kTOWYYjHmz2PUBmzHxWkCZRrOQiGogEePVII=";
  cargoHash = "sha256-uoKVa3SVGaWAoJ5o3VL+FI9d843OJyR2x0NnGx9azC0=";
  description = "Presentation and slide-show editor (PPTX/ODP interchange, PDF export)";
  homepage = "https://getartcraft.com/apps/deckcraft";
  extraBuildInputs = [ alsa-lib ];
}
