##
# Package: protoplug
# Purpose: Protoplug 1.4.0 — JUCE VST2 plugins (Lua Protoplug Fx/Gen) that load
#   and live-edit LuaJIT scripts as audio effects/instruments in a DAW
#   (live-coding environment; MIT). VST2 SDK (vstsdk2.4_minimal) and JUCE are
#   vendored in the source tree; built with the JUCE-generated Linux makefiles.
{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  alsa-lib,
  atk,
  cairo,
  curl,
  fftw,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  harfbuzz,
  pango,
  libx11,
  libxext,
  libxinerama,
  luajit,
}:

stdenv.mkDerivation rec {
  pname = "protoplug";
  version = "1.4.0";

  patches = [ ./juce-pixelformats-gcc.patch ]; # GCC 13+ packed-field ref bindings

  src = fetchurl {
    name = "protoplug-1.4.0.tar.gz";
    url = "https://codeload.github.com/pac-dev/protoplug/tar.gz/refs/tags/v1.4.0";
    sha256 = "11n8j7nx2g6yjd2x61bnp54f42bigjg1kyh9c9vvcw933mc7mzb9";
  };

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    alsa-lib
    atk
    cairo
    curl
    fftw
    freetype
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    luajit
    pango
    libx11
    libxext
    libxinerama
  ];

  env.NIX_CFLAGS_COMPILE = "-I${luajit}/include/luajit-2.1";

  buildPhase = ''
    runHook preBuild
    make -C Builds/multi/Linux CONFIG=Release -j"$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/vst $out/share
    cp "Bin/linux/Lua Protoplug Fx.so" $out/lib/vst/
    cp "Bin/linux/Lua Protoplug Gen.so" $out/lib/vst/
    cp -r ProtoplugFiles $out/share/ProtoplugFiles
    runHook postInstall
  '';

  postFixup = ''
    rpath=${lib.makeLibraryPath buildInputs}:${lib.getLib stdenv.cc.cc}/lib
    for p in $out/lib/vst/*.so; do
      patchelf --set-rpath "$rpath" "$p"
    done
  '';

  meta = {
    description = "Protoplug — Lua live-coding VST2 plugins (Fx + Gen)";
    homepage = "https://www.osar.fr/protoplug/";
    sourceProvenance = with lib.sourceTypes; [ sourceFromSource ];
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
