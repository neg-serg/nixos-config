# WordCraft — Word-style word processor (ribbon UI, track changes, references,
# mail merge) plus its converter CLI (docx/pdf/odt/rtf/html/md/tex/txt/png).
#
# Built from the upstream release tag. The workspace also ships an experimental
# web front end (apps/wordcraft-web) and an xtask helper; only the two binaries
# that packaging/linux/package.sh stages for the official Linux packages are
# built here.
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
  libxcursor,
  libxrandr,
  libxi,
}:

let
  # Upstream bakes the commit and build date in from git when packaging; the
  # Nix substitute is the release tag's commit (the About dialog would show
  # "development build" without it).
  buildSha = "7dfa6b0ee2aeeafec004c51fdd2ab9a697da3cc4";
  buildDate = "2026-10-12"; # commit date of v0.6.1

  # wgpu (Vulkan/GL), winit and the Wayland client dlopen these at runtime —
  # nothing links them, so they go on the wrapper's LD_LIBRARY_PATH.
  runtimeLibs = [
    vulkan-loader # wgpu's Vulkan backend
    libGL # wgpu's GL fallback (libEGL/libGL from libglvnd)
    libxkbcommon # winit keyboard handling
    wayland # libwayland-client (wayland backend)
    libx11
    libxcursor
    libxrandr
    libxi
  ];
in
rustPlatform.buildRustPackage rec {
  pname = "wordcraft";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "wordcraft";
    tag = "v${version}";
    hash = "sha256-10djkguZ4kJBvZTH5Oni5D0XZrfe1gayy7WhsBlpd+0=";
  };

  cargoHash = "sha256-L9NqKB/K/giJ4PmyevB389BHG2jEATHjWnGa15BVyUM=";

  # Two binaries, as in the official packages; `-p` also keeps xtask out of
  # the build (and therefore out of $out/bin).
  cargoBuildFlags = [
    "--locked"
    "-p"
    "wordcraft"
    "-p"
    "wordcraft-cli"
  ];

  # The workspace's ~800 tests are upstream's `cargo xtask ci` job: they cover
  # the whole crate tree (web included) and would roughly double the build.
  # The packaged binaries are smoke-tested instead (CLI conversion + GUI start).
  doCheck = false;

  env = {
    WORDCRAFT_BUILD_SHA = buildSha;
    WORDCRAFT_BUILD_DATE = buildDate;
  };

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    for prog in wordcraft wordcraft-cli; do
      wrapProgram "$out/bin/$prog" --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
    done
  '';

  # Desktop entry, MIME types, AppStream metainfo and icons: the same files
  # packaging/linux/package.sh installs for the .deb/.rpm/AppImage, so file
  # managers and the launcher see WordCraft as the handler for Word documents.
  postInstall = ''
    install -Dm644 packaging/linux/ai.storyteller.wordcraft.desktop \
      $out/share/applications/ai.storyteller.wordcraft.desktop
    install -Dm644 packaging/linux/ai.storyteller.wordcraft.mime.xml \
      $out/share/mime/packages/ai.storyteller.wordcraft.xml
    mkdir -p $out/share/metainfo
    sed \
      -e "s/@VERSION@/${version}/g" \
      -e "s/@DATE@/${buildDate}/g" \
      packaging/linux/ai.storyteller.wordcraft.metainfo.xml.in \
      >$out/share/metainfo/ai.storyteller.wordcraft.metainfo.xml
    mkdir -p $out/share/icons
    cp -R assets/app-icon/hicolor $out/share/icons/hicolor

    mkdir -p $out/share/doc/wordcraft
    install -m644 LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md \
      $out/share/doc/wordcraft/
  '';

  meta = lib.mkMeta {
    description = "Word-style word processor and document converter (.docx/.odt/.rtf)";
    homepage = "https://github.com/storytold/wordcraft";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    mainProgram = "wordcraft";
  };
}
