#
# sonda — a file manager whose search knows what the files hold
#
#
# Upstream: https://github.com/k4ditano/sonda (MIT). A file manager for pleamar-wm (and any Wayland
# compositor) that finds files by what is inside them: EmbeddingGemma 2 embeddings over photos, PDF
# pages, audio, video and code, computed locally on llama.cpp (Vulkan).
#
# ## Why two derivations in one file
#
# sonda is not self-contained: `build.rs` compiles `csrc/embed.c` against llama.cpp's *source*
# headers (llama.h, ggml-backend.h, tools/mtmd/mtmd.h — the C layer calls the mtmd API) and links
# the Rust binary against libmtmd/libllama/libggml*, then bakes two rpaths into it
# (`$ORIGIN/../lib/sonda` and the build-time lib dir). Upstream pins one llama.cpp tag for that
# (b11461 in `scripts/build-llama.sh`) together with a one-line patch: a non-causal embedding
# context must not reserve n_vocab logits per token, which for Gemma's 262k vocabulary is ~1 MiB
# per token. So the llama.cpp build lives here as a private derivation — headers from its `src`
# (the patch only touches `src/llama-context.cpp`, no header changes), libraries from its `$out/lib`.
#
# ## Layout
#
# `$out/bin/sonda`, the llama.cpp libraries in `$out/lib/sonda` (the rpath upstream expects, so the
# binary also runs when moved), and the xdg-desktop-portal backend file in
# `$out/share/xdg-desktop-portal/portals/sonda.portal`. The window itself is not installed: its
# `.plm` scene, Lua and shaders are `include_str!`-ed into the binary and `sonda setup` writes them
# to `$XDG_DATA_HOME/sonda/ui`. The models (865 MB) are downloaded by `sonda setup` on first run,
# not pinned here — see the note in the module that installs this.
#
# ## Runtime tools
#
# sonda shells out for the heavy lifting (bsdtar to pack/unpack, ffmpeg for video frames and
# ffplay for the in-window player, pdftoppm/pdftotext for PDFs, gio for the trash, wl-copy for the
# clipboard, `file` and xdg-mime for kinds, curl for the model download), so the wrapper puts them
# on PATH (util-linux for `setsid`, which starts the reader, and `lsblk`, for the partition table).
# `udisksctl` stays out on purpose: it is the udisks2 *daemon's* client, and that service is the
# platform's, so the wrapper lets the inherited PATH reach the system's copy.
#
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  ninja,
  shaderc,
  vulkan-headers,
  vulkan-loader,
  makeWrapper,
  curl,
  ffmpeg,
  file,
  glib,
  libarchive,
  poppler-utils,
  util-linux,
  wl-clipboard,
  xdg-utils,
}:
let
  # The tag `scripts/build-llama.sh` pins, and its commit (the tag is mutable; the commit is not).
  llamaVersion = "b11461";
  llamaRev = "4d756bc72bf00a4aacf410ae15a2d315f3db400d";

  llama-cpp = stdenv.mkDerivation {
    pname = "llama-cpp-sonda";
    version = llamaVersion;

    src = fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = llamaRev;
      hash = "sha256-RLPfPr+5yjQsWDpOSD1tGGNNThxYgTV6Bm3mh/pOC2E=";
    };

    patches = [ ./llama.cpp-no-logits.patch ];

    # GGML_VULKAN needs glslc (shaderc) to compile the shaders and the Vulkan headers to compile
    # against; the loader is dlopen'ed at run time.
    nativeBuildInputs = [
      cmake
      ninja
      shaderc
    ];
    buildInputs = [
      vulkan-headers
      vulkan-loader
    ];

    # Upstream's flag set, minus the Vulkan probe: `GGML_NATIVE=ON` is kept because this build is
    # for this host only (a faster CPU feature set than nixpkgs' baseline), and the tests are off
    # (some of them want the network), so there is nothing for ctest to run.
    cmakeFlags = [
      "-DBUILD_SHARED_LIBS=ON"
      "-DGGML_VULKAN=ON"
      "-DGGML_NATIVE=ON"
      "-DLLAMA_BUILD_TESTS=OFF"
      "-DLLAMA_BUILD_EXAMPLES=OFF"
      "-DLLAMA_BUILD_SERVER=OFF"
      "-DLLAMA_BUILD_TOOLS=ON"
      "-DLLAMA_BUILD_MTMD=ON"
      "-DLLAMA_OPENSSL=OFF"
      "-DLLAMA_CURL=OFF"
      "-DLLAMA_BUILD_APP=OFF"
      "-DLLAMA_BUILD_UI=OFF"
    ];
    doCheck = false;

    meta = {
      description = "llama.cpp pinned for sonda (EmbeddingGemma 2, Vulkan, mtmd)";
      homepage = "https://github.com/ggml-org/llama.cpp";
      license = lib.licenses.mit;
    };
  };
in
rustPlatform.buildRustPackage {
  pname = "sonda";
  # No release upstream: the version is the date of the pinned commit.
  version = "0.1.0-unstable-2026-10-29";

  src = fetchFromGitHub {
    owner = "k4ditano";
    repo = "sonda";
    rev = "d829895a0a132ac2e7f38d23fe275f98930edce9";
    hash = "sha256-7Adt7Ultw6ubo90G56jo5u11FDlVLr+Ns7a71ADtX6k=";
  };

  cargoHash = "sha256-Lq83giZ4Aaq3AL7P/r/PllCj1KCf7/3ehcD4pHGhThs=";

  # `build.rs` resolves the headers as `$CARGO_MANIFEST_DIR/vendor/llama.cpp` — the tree upstream's
  # `scripts/build-llama.sh` clones next to the sources — and the libraries from
  # `$SONDA_LLAMA_LIBS`, defaulting to `vendor/llama-build/bin`. Only the libraries move: the
  # headers come from the llama.cpp source tree, which is exactly what `llama-cpp.src` is.
  postUnpack = ''
    mkdir -p "$sourceRoot/vendor"
    ln -s ${llama-cpp.src} "$sourceRoot/vendor/llama.cpp"
  '';
  env.SONDA_LLAMA_LIBS = "${llama-cpp}/lib";

  # No test target upstream (`cargo test` builds the harness for nothing).
  doCheck = false;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # Upstream's layout: beside the binary, for the `$ORIGIN/../lib/sonda` rpath...
    install -d "$out/lib/sonda"
    for lib in ${llama-cpp}/lib/lib*.so*; do
      cp -a "$lib" "$out/lib/sonda/"
    done
    # ...and the Open/Save dialog backend, in the place xdg-desktop-portal looks.
    install -Dm644 ${./sonda.portal} "$out/share/xdg-desktop-portal/portals/sonda.portal"

    wrapProgram "$out/bin/sonda" \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          ffmpeg
          file
          glib
          libarchive
          poppler-utils
          util-linux
          wl-clipboard
          xdg-utils
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader ]}
  '';

  meta = {
    description = "File manager for pleamar-wm that finds your files by what is in them";
    longDescription = ''
      Sonda walks the file system like a file manager and searches it by meaning: photos by what
      they show, a PDF at the page, a recording at the minute, code at the line. The embeddings come
      from Google DeepMind's EmbeddingGemma 2 on llama.cpp (Vulkan), all local. Its window is a
      pleamar scene, so it needs pleamar (or pleamar-wm) on PATH; on any other Wayland compositor it
      runs as a normal window.
    '';
    homepage = "https://github.com/k4ditano/sonda";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "sonda";
  };
}
