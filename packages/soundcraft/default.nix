# SoundCraft — digital audio workstation (multitrack recording, editing and
# mixing, MIDI, plugin hosting) plus its `soundcraft-cli` companion.
#
# Upstream: https://github.com/storytold/soundcraft (MIT OR Apache-2.0). Built
# from the release tag through lib/mkCraftApp.nix. ALSA is linked by the cpal
# backend (alsa-sys resolves it through pkg-config), not dlopen'ed.
{
  neg,
  alsa-lib,
  ...
}:
neg.functions.mkCraftApp {
  name = "soundcraft";
  version = "0.18.0";
  hash = "sha256-KxTP6R6jrGVX9SkMEepccThk3FKIhn+V7e01kXLIIZQ=";
  cargoHash = "sha256-ExKqLiUi8EeqJyvftaNwpdx/oYuQ/nnVqefXBC9jVCM=";
  description = "Digital audio workstation (multitrack recording, editing, mixing, MIDI)";
  homepage = "https://getartcraft.com/apps/soundcraft";
  extraBuildInputs = [ alsa-lib ];
}
