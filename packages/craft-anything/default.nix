# Craft Anything — reverse-engineering workbench: reads executables, libraries,
# archives, Android packages, WebAssembly and web bundles, disassembles and
# decompiles them, keeps an evidence ledger for every answer, and drives a
# coding agent that rebuilds a target the user asked for.
#
# Built from the upstream release tag. The workspace ships three front ends;
# only the two native binaries that packaging/linux/package.sh puts into the
# .deb/.rpm/AppImage are built here: `apps/craft-anything-web` is a wasm target
# and the `xtask` helper is upstream's CI driver.
#
# wgpu (Vulkan, with the GL fallback), winit (X11/Wayland, xkbcommon) and rfd
# (the XDG portal) load what they need at run time, so the binaries link
# neither and the wrapper carries the same library list that the .deb declares
# as Depends. libXrandr and fontconfig are deliberately absent: RandR goes
# through x11rb's protocol code and the app finds fonts by scanning
# directories (packaging/linux/nfpm.yaml).
#
# Upstream's test suite is `cargo xtask ci` over the whole crate tree (it wants
# real targets, network and an agent), so it is off here; the packaged binaries
# are smoke-tested instead.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  vulkan-loader,
  libGL,
  libxkbcommon,
  wayland,
  libx11,
  libxcb,
  libxcursor,
  libxi,
}:

rustPlatform.buildRustPackage rec {
  pname = "craft-anything";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-anything";
    tag = "v${version}";
    hash = "sha256-wHQHqEpRW+eypP0y+rafAz8CBi/ei8lka8st5JxpqL4=";
  };

  cargoHash = "sha256-KcO+GSt9XlmrPbUrO4uF9TXj6BvgFF8XrZfI3eiyibk=";

  # `-p` keeps the wasm front end and xtask out of the build (and therefore
  # out of $out/bin); upstream's packages ship exactly these two binaries.
  cargoBuildFlags = [
    "--locked"
    "-p"
    "craft-anything"
    "-p"
    "craft-anything-cli"
  ];

  doCheck = false;

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    for prog in craft-anything craft-anything-cli; do
      wrapProgram "$out/bin/$prog" --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          vulkan-loader # wgpu's Vulkan backend
          libGL # wgpu's GL fallback (libEGL/libGL from libglvnd)
          libxkbcommon # winit keyboard handling (X11 and Wayland)
          wayland # libwayland-client (Wayland backend)
          libx11
          libxcb
          libxcursor
          libxi
        ]
      }"
    done
  '';

  # The desktop entry, AppStream metainfo and icons are the files the official
  # Linux packages install. The module that puts the app on PATH also ships a
  # makeDesktopItem, because this package is deliberately kept out of the
  # system closure and its own share/ tree is therefore never on the system
  # XDG_DATA_DIRS.
  postInstall = ''
    install -Dm644 packaging/linux/ai.storyteller.craft-anything.desktop \
      $out/share/applications/ai.storyteller.craft-anything.desktop
    mkdir -p $out/share/metainfo
    sed -e "s/@VERSION@/${version}/g" -e "s/@DATE@/1970-01-01/g" \
      packaging/linux/ai.storyteller.craft-anything.metainfo.xml.in \
      >$out/share/metainfo/ai.storyteller.craft-anything.metainfo.xml
    mkdir -p $out/share/icons
    cp -R assets/app-icon/hicolor $out/share/icons/hicolor

    mkdir -p $out/share/doc/craft-anything
    install -m644 README.md LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md \
      $out/share/doc/craft-anything/
  '';

  meta = lib.mkMeta {
    description = "Reverse-engineering workbench and rebuild assistant (desktop app, CLI, MCP server)";
    homepage = "https://github.com/storytold/craft-anything";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    mainProgram = "craft-anything";
  };
}
