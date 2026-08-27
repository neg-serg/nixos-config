##
# Package: mi-ugens
# Purpose: Mutable Instruments eurorack modules ported to SuperCollider
#   (Clouds, Elements, Rings, Plaits, Braids, Tides, Warps, Grids, Verb, …).
#   Server plugins (.so) plus SC class files.
# Source: https://github.com/v7b1/mi-UGens
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "mi-ugens";
  version = "unstable-2026-04-10";

  src = fetchFromGitHub {
    owner = "v7b1";
    repo = "mi-UGens";
    rev = "10f6824f68ad63475f67dfe3fe5016e2d2634f84";
    hash = "sha256-16XeG3wXGPkiLd9oi6ZNF7jbndbKeVvf6hP/Verm2zg=";
  };

  # MiBraids links a static libsamplerate that upstream keeps as a git
  # submodule (fetchFromGitHub does not fetch submodules). Fetch the exact
  # submodule rev and unpack it into place before configuring.
  libsamplerate = fetchFromGitHub {
    owner = "libsndfile";
    repo = "libsamplerate";
    rev = "2ccde9568cca73c7b32c97fefca2e418c16ae5e3";
    hash = "sha256-GmgfmdrawAK8ktKtMgHMnzD2p80e373YNYlGg1edF/Q=";
  };

  postUnpack = ''
    rm -rf "$sourceRoot/projects/MiBraids/libsamplerate"
    cp -r ${libsamplerate} "$sourceRoot/projects/MiBraids/libsamplerate"
    chmod -R u+w "$sourceRoot/projects/MiBraids/libsamplerate"
  '';

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
  ];

  # Parallel make race: MiBraids links libsamplerate.a by path without a
  # declared dependency, so the first parallel pass can fail with "No rule to
  # make target ... libsamplerate.a". Build that target first, then the rest.
  preBuild = ''
    cmake --build . --target samplerate
  '';

  postInstall = ''
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/mi-UGens"
    mv "$out/mi-UGens"/*.so "$out/lib/SuperCollider/plugins/"
    cp -r "$out/mi-UGens/Classes" "$out/share/SuperCollider/extensions/mi-UGens/"
    cp -r "$out/mi-UGens/HelpSource" "$out/share/SuperCollider/extensions/mi-UGens/"
    rm -rf "$out/mi-UGens"
  '';

  meta = with lib; {
    description = "Mutable Instruments eurorack modules as SuperCollider UGens";
    homepage = "https://github.com/v7b1/mi-UGens";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
