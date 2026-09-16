##
# Package: sc-faust
# Purpose: sc_faust — JIT-compile Faust DSP code directly in scsynth as the
#   Faust UGen (grame-cncm/faust statically linked, incl. LLVM backend).
#   Includes jpverb (Freedesktop noise-reduction/plate reverb) examples.
# Source: https://github.com/capital-G/sc_faust (GPL-3); release v0.1.2 binary.
{
  lib,
  stdenv,
  stdenvNoCC,
  unzip,
  patchelf,
  zlib,
  ncurses,
}:
stdenvNoCC.mkDerivation rec {
  pname = "sc-faust";
  version = "0.1.2";

  # GitHub is blocked on this host — release archive staged locally.
  # Upstream release: sc_faust-0.1.2-linux-x86-64.zip (119 MB .so, statically
  # linked libfaustwithllvm + faustlibs).
  # In-repo copy so pure evaluation works (absolute paths outside the flake are forbidden).
  src = ./sc_faust.zip;

  nativeBuildInputs = [
    unzip
    patchelf
  ];
  buildInputs = [
    zlib
    ncurses
  ];
  # The release .so is a prebuilt binary with no rpath — point it at the nix
  # store libs it needs (libz, libtinfo, libstdc++ from the stdenv cc).
  postFixup = ''
    patchelf --set-rpath "${
      lib.makeLibraryPath [
        zlib
        ncurses
        stdenv.cc.cc.lib
      ]
    }" \
      "$out/lib/SuperCollider/plugins/sc_faust.so"
  '';

  unpackPhase = ''
    unzip -q $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/sc_faust"
    cp -v sc_faust/sc_faust.so "$out/lib/SuperCollider/plugins/"
    cp -rv sc_faust/Classes "$out/share/SuperCollider/extensions/sc_faust/"
    cp -rv sc_faust/HelpSource "$out/share/SuperCollider/extensions/sc_faust/"
    cp -rv sc_faust/externals "$out/share/SuperCollider/extensions/sc_faust/"
    cp -v sc_faust/README.md sc_faust/LICENSE "$out/share/SuperCollider/extensions/sc_faust/"

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "SuperCollider plugin: JIT-compile Faust DSP in scsynth (Faust UGen, incl. jpverb reverb)";
    homepage = "https://github.com/capital-G/sc_faust";
    license = lib.licenses.gpl3;
  };
}
