# SolidCraft — parametric 3D CAD: sketches with a constraint solver, a
# parametric feature timeline, components and joints, sheet metal; STEP, IGES,
# 3MF, STL and OBJ. Ships `solidcraft-cli` (headless command runner and MCP
# server) and the `solvecraft-cli` compatibility shim for the pre-rename name.
#
# Upstream: https://github.com/tangency-labs/solidcraft (MIT OR Apache-2.0).
# Built from the release tag through lib/mkCraftApp.nix. Its desktop entry,
# MIME xml and icons live under assets/platforms/linux and
# assets/icons/app/linux instead of the packaging/linux copy the other five use,
# and file dialogs fall back to zenity without a desktop portal (upstream's
# nix/flake.nix wraps the binary the same way).
{
  neg,
  libxrandr,
  libxrender,
  libxext,
  zenity,
  ...
}:
neg.functions.mkCraftApp {
  name = "solidcraft";
  version = "0.30.1";
  owner = "tangency-labs";
  hash = "sha256-OBFZLKF/qnO2wzDpVcyTHJoxHyHw7+hi41zJXim/4GE=";
  cargoHash = "sha256-/335aT/yANzBtrsEc7byA54IJxMqNeAGktBr5/sSDAo=";
  description = "Parametric 3D CAD (constraint sketches, feature timeline, STEP/IGES/3MF/STL)";
  homepage = "https://docs.solidcraft.io/";
  appId = "io.tangencylabs.solidcraft";
  desktop = "assets/platforms/linux/io.tangencylabs.solidcraft.desktop";
  mime = "assets/platforms/linux/io.tangencylabs.solidcraft.mime.xml";
  metainfo = "assets/platforms/linux/io.tangencylabs.solidcraft.metainfo.xml.in";
  icons = "assets/icons/app/linux/exports/hicolor";
  binaries = [
    "solidcraft"
    "solidcraft-cli"
    "solvecraft-cli"
  ];
  docs = [
    "README.md"
    "NOTICE"
    "ATTRIBUTION.md"
    "DISCLAIMER.md"
    "THIRD-PARTY-LICENSES.txt"
    "LICENSE-MIT"
    "LICENSE-APACHE"
  ];
  extraRuntimeLibs = [
    # mkCraftApp's common set plus the X11 extensions the app's own flake
    # declares for the XWayland (drag and drop) path.
    libxrandr
    libxrender
    libxext
  ];
  wrapperPath = [ zenity ];
}
