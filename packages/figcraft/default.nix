# FigCraft — interface design and prototyping (canvas with text tools, Auto
# Layout-style resizing, components and variants, prototyping links) plus its
# `figcraft-cli` companion.
#
# Upstream: https://github.com/storytold/figcraft (MIT OR Apache-2.0). Built
# from the release tag through lib/mkCraftApp.nix; the workspace's
# `apps/figcraft-server` and wasm front end are not built.
{
  neg,
  ...
}:
neg.functions.mkCraftApp {
  name = "figcraft";
  version = "0.16.0";
  hash = "sha256-FFQtIH9UkI0Kw7OcxSIDdQJrx/gHe35GToeY0O0SMdk=";
  cargoHash = "sha256-0FLmpKGE2D20BU31a1abRQ6M/uW9yU/mzUNyn+WkMPM=";
  description = "Interface design and prototyping app (design canvas, components, prototyping)";
  homepage = "https://getartcraft.com/apps/figcraft";
}
