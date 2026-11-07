# VectorCraft — vector illustration editor (pen/brush/shape tools, artboards,
# symbols, live effects; reads and writes SVG and PDF) plus its headless
# converter `vectorcraft-cli`.
#
# Upstream: https://github.com/storytold/vectorcraft (MIT OR Apache-2.0). Built
# from the release tag through lib/mkCraftApp.nix, which also embeds the
# craft-fonts faces the official packages ship.
{
  lib,
  neg,
  ...
}:
neg.functions.mkCraftApp {
  name = "vectorcraft";
  version = "0.22.0";
  hash = "sha256-4Cb7wS6IxhGsQ8O4CdbjDJtYu8Z3NoHhUzxbRWziYYA=";
  cargoHash = "sha256-wXaN0TDkhMT6SgOH5HO1NSVsvB3vT1bghEomOF3BYkc=";
  description = "Vector illustration editor (SVG/PDF) with a headless converter CLI";
  homepage = "https://getartcraft.com/apps/vectorcraft";
  # The embedded craft-fonts faces are OFL on top of the app's own MIT/Apache-2.
  license = lib.licenses.AND [
    (lib.licenses.OR [
      lib.licenses.mit
      lib.licenses.asl20
    ])
    lib.licenses.ofl
  ];
}
